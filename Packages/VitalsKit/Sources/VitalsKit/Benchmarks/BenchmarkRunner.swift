import Foundation
#if canImport(Metal)
import Metal
#endif

/// A short benchmark: CPU single- and multi-thread, one Metal compute pass, storage write and read.
/// Sized to finish well under 10 seconds on a recent iPhone, and refused at serious or critical heat
/// (it would only measure throttling and add heat).
public enum BenchmarkRunner {
    public enum Stage: String, Sendable, CaseIterable { case cpuSingle, cpuMulti, gpu, storageWrite, storageRead
        public var label: String {
            switch self {
            case .cpuSingle: "CPU, one core"
            case .cpuMulti: "CPU, all cores"
            case .gpu: "Graphics (Metal compute)"
            case .storageWrite: "Storage write"
            case .storageRead: "Storage read"
            }
        }
    }

    public enum BenchError: Error, CustomStringConvertible {
        case tooHot(ThermalLevel)
        public var description: String {
            switch self { case .tooHot(let t): "The phone is \(t.label.lowercased()). Let it cool to Normal or Warm first; a hot phone only measures throttling." }
        }
    }

    /// Fixed work for the CPU stages: iterations of a mixed integer/float loop.
    static let cpuIterations = 30_000_000

    public static func run(thermal: () -> ThermalLevel, lowPowerMode: Bool, modelIdentifier: String, cores: Int,
                           tempDirectory: URL = FileManager.default.temporaryDirectory, scale: Double = 1,
                           progress: (Stage) -> Void) throws -> BenchmarkResult {
        let startThermal = thermal()
        guard !startThermal.isHot else { throw BenchError.tooHot(startThermal) }
        let t0 = Date()
        var scores: [BenchmarkResult.Score] = []
        let baseline = BaselineTable.entry(for: modelIdentifier)

        func add(_ s: Stage, _ value: Double, _ unit: String, _ secs: Double) {
            scores.append(.init(id: s.rawValue, label: s.label, value: value, unit: unit, seconds: secs, expected: baseline?[s.rawValue]))
        }

        // CPU stages do fixed-size chunks until the work is done or a time cap is reached, so the whole
        // benchmark stays under 10 s even on a slow or throttled phone. Score = work done ÷ time taken.
        progress(.cpuSingle)
        let n = Int(Double(cpuIterations) * scale)
        let (doneSingle, single) = time { boundedCPU(total: n, cap: cpuCap) }
        add(.cpuSingle, Double(doneSingle) / single / 1e6, "M ops/s", single)

        progress(.cpuMulti)
        let threads = max(1, cores)
        let counter = Counter()
        let (_, multi) = time {
            DispatchQueue.concurrentPerform(iterations: threads) { _ in counter.add(boundedCPU(total: n, cap: cpuCap)) }
        }
        add(.cpuMulti, Double(counter.value) / multi / 1e6, "M ops/s", multi)

        progress(.gpu)
        if let (gflops, secs) = gpuPass(scale: scale) { add(.gpu, gflops, "GFLOPS", secs) }

        progress(.storageWrite)
        let (w, r, ws, rs) = try storagePass(dir: tempDirectory, megabytes: max(4, Int(128 * scale)))
        add(.storageWrite, w, "MB/s", ws)
        progress(.storageRead)
        add(.storageRead, r, "MB/s", rs)

        return BenchmarkResult(takenAt: t0, modelIdentifier: modelIdentifier, thermalAtStart: startThermal, thermalAtEnd: thermal(),
                               lowPowerMode: lowPowerMode, scores: scores, totalSeconds: Date().timeIntervalSince(t0), hasBaseline: baseline != nil)
    }

    static func time<T>(_ f: () throws -> T) rethrows -> (T, Double) {
        let s = DispatchTime.now().uptimeNanoseconds
        let r = try f()
        return (r, max(1e-6, Double(DispatchTime.now().uptimeNanoseconds - s) / 1e9))
    }

    static let cpuCap: Double = 2.0

    /// Runs `cpuWork` in 1M-iteration chunks until `total` is done or `cap` seconds pass. Returns iterations done.
    static func boundedCPU(total: Int, cap: Double) -> Int {
        let start = DispatchTime.now().uptimeNanoseconds
        let chunk = 1_000_000
        var done = 0
        var sink: UInt64 = 0
        while done < total {
            let k = min(chunk, total - done)
            sink &+= cpuWork(k)
            done += k
            if Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 > cap { break }
        }
        if sink == 42 { print("") } // keep the work observable
        return done
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var v = 0
        func add(_ x: Int) { lock.lock(); v += x; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return v }
    }

    /// Integer xorshift mixed with float multiply-add, so neither unit alone decides the score.
    @inline(never)
    static func cpuWork(_ n: Int) -> UInt64 {
        var x: UInt64 = 88172645463325252
        var f: Double = 1.0001
        for _ in 0..<n {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            f = f * 1.0000001 + Double(x & 0xff) * 1e-12
        }
        return x &+ UInt64(f.bitPattern & 1)
    }

    static func gpuPass(scale: Double) -> (Double, Double)? {
        #if canImport(Metal)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void fma_loop(device float *data [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            float a = data[id], b = 1.000001f, c = 0.999999f;
            for (int i = 0; i < 256; i++) { a = fma(a, b, c); b = fma(b, c, a * 1e-7f); }
            data[id] = a + b;
        }
        """
        guard let lib = try? device.makeLibrary(source: source, options: nil), let fn = lib.makeFunction(name: "fma_loop"),
              let pipeline = try? device.makeComputePipelineState(function: fn) else { return nil }
        let count = Int(4_000_000 * scale)
        guard let buffer = device.makeBuffer(length: count * 4, options: .storageModeShared) else { return nil }
        let p = buffer.contents().bindMemory(to: Float.self, capacity: count)
        for i in 0..<count { p[i] = Float(i % 97) * 0.01 }
        func dispatch() -> Double {
            guard let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return 0 }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(buffer, offset: 0, index: 0)
            let w = pipeline.threadExecutionWidth
            enc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
            enc.endEncoding()
            let s = DispatchTime.now().uptimeNanoseconds
            cb.commit(); cb.waitUntilCompleted()
            return Double(DispatchTime.now().uptimeNanoseconds - s) / 1e9
        }
        _ = dispatch() // warm-up
        let secs = max(1e-6, dispatch())
        let flops = Double(count) * 256 * 4   // two FMAs per iteration, two flops each
        return (flops / secs / 1e9, secs)
        #else
        return nil
        #endif
    }

    /// Writes then reads a temporary file with the cache bypassed (F_NOCACHE), then deletes it.
    static func storagePass(dir: URL, megabytes: Int) throws -> (Double, Double, Double, Double) {
        let url = dir.appendingPathComponent("vitals-bench-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let chunk = Data((0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 2654435761) })
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let wh = try FileHandle(forWritingTo: url)
        _ = fcntl(wh.fileDescriptor, F_NOCACHE, 1)
        let (_, ws) = try time {
            for _ in 0..<megabytes { try wh.write(contentsOf: chunk) }
            try wh.synchronize()
        }
        try wh.close()
        let rh = try FileHandle(forReadingFrom: url)
        _ = fcntl(rh.fileDescriptor, F_NOCACHE, 1)
        let (_, rs) = try time {
            while let d = try rh.read(upToCount: 1 << 20), !d.isEmpty {}
        }
        try rh.close()
        return (Double(megabytes) / ws, Double(megabytes) / rs, ws, rs)
    }
}

/// Expected ranges per model, bundled. Deliberately empty in v1.0: Vitals publishes no number it has not
/// measured, so ranges are added only from real runs on real phones (start with the iPhone Duo).
/// Until then every result says "no baseline for this model".
public enum BaselineTable {
    struct File: Decodable { let models: [String: [String: [Double]]] }

    static let table: [String: [String: ClosedRange<Double>]] = {
        guard let url = Bundle.module.url(forResource: "benchmark-baselines", withExtension: "json"),
              let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return f.models.mapValues { stages in stages.compactMapValues { $0.count == 2 && $0[0] <= $0[1] ? $0[0]...$0[1] : nil } }
    }()

    public static func entry(for model: String) -> [String: ClosedRange<Double>]? {
        guard let e = table[model], !e.isEmpty else { return nil }
        return e
    }
}

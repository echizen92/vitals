import Foundation

/// The user-started network test. The only network use in Vitals.
public enum NetworkTestConfig {
    /// One constant to change the endpoint (plan §5.6 / §9). Cloudflare's public speed-test endpoints:
    /// `GET /__down?bytes=N` returns N bytes, `POST /__up` accepts a body.
    public static let base = URL(string: "https://speed.cloudflare.com")!
    public static let downloadBytes = 25_000_000
    public static let uploadBytes = 5_000_000
    public static let latencyProbes = 8
}

public struct NetworkTestResult: Codable, Sendable, Hashable {
    public var takenAt: Date
    public var endpoint: String
    public var interfaces: String
    public var dnsMilliseconds: Double?
    public var latencyMilliseconds: Double?
    public var jitterMilliseconds: Double?
    public var downloadMbps: Double?
    public var uploadMbps: Double?
    public var errors: [String]

    public init(takenAt: Date, endpoint: String, interfaces: String, dnsMilliseconds: Double?, latencyMilliseconds: Double?,
                jitterMilliseconds: Double?, downloadMbps: Double?, uploadMbps: Double?, errors: [String]) {
        self.takenAt = takenAt; self.endpoint = endpoint; self.interfaces = interfaces; self.dnsMilliseconds = dnsMilliseconds
        self.latencyMilliseconds = latencyMilliseconds; self.jitterMilliseconds = jitterMilliseconds; self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps; self.errors = errors
    }
}

public enum NetworkTester {
    public enum Stage: String, Sendable { case dns, latency, download, upload }

    /// Median and jitter (mean absolute difference between consecutive probes).
    public static func summarize(_ ms: [Double]) -> (median: Double, jitter: Double)? {
        guard !ms.isEmpty else { return nil }
        let s = ms.sorted()
        let median = s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        let diffs = zip(ms, ms.dropFirst()).map { abs($0 - $1) }
        return (median, diffs.isEmpty ? 0 : diffs.reduce(0, +) / Double(diffs.count))
    }

    public static func mbps(bytes: Int, seconds: Double) -> Double { Double(bytes) * 8 / max(seconds, 1e-6) / 1e6 }

    public static func run(interfaces: String, progress: @Sendable (Stage) -> Void) async -> NetworkTestResult {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let base = NetworkTestConfig.base
        var errors: [String] = []
        let collector = MetricsCollector()

        progress(.dns)
        // DNS: the domain lookup phase of the first request on a fresh session.
        var dns: Double?
        do {
            let (_, _) = try await session.data(from: base.appendingPathComponent("__down").appending(queryItems: [.init(name: "bytes", value: "0")]), delegate: collector)
            dns = collector.last?.dnsMilliseconds
        } catch { errors.append("DNS/first request: \(error.localizedDescription)") }

        progress(.latency)
        var rtts: [Double] = []
        for _ in 0..<NetworkTestConfig.latencyProbes {
            do {
                let (_, _) = try await session.data(from: base.appendingPathComponent("__down").appending(queryItems: [.init(name: "bytes", value: "0")]), delegate: collector)
                if let r = collector.last?.responseMilliseconds { rtts.append(r) }
            } catch { errors.append("Latency: \(error.localizedDescription)"); break }
        }
        let lat = summarize(rtts)

        progress(.download)
        var down: Double?
        do {
            let url = base.appendingPathComponent("__down").appending(queryItems: [.init(name: "bytes", value: "\(NetworkTestConfig.downloadBytes)")])
            let start = Date()
            let (data, _) = try await session.data(from: url, delegate: collector)
            down = mbps(bytes: data.count, seconds: Date().timeIntervalSince(start))
        } catch { errors.append("Download: \(error.localizedDescription)") }

        progress(.upload)
        var up: Double?
        do {
            var req = URLRequest(url: base.appendingPathComponent("__up"))
            req.httpMethod = "POST"
            let body = Data(count: NetworkTestConfig.uploadBytes)
            let start = Date()
            _ = try await session.upload(for: req, from: body, delegate: collector)
            up = mbps(bytes: body.count, seconds: Date().timeIntervalSince(start))
        } catch { errors.append("Upload: \(error.localizedDescription)") }

        return NetworkTestResult(takenAt: .now, endpoint: base.host() ?? base.absoluteString, interfaces: interfaces, dnsMilliseconds: dns,
                                 latencyMilliseconds: lat?.median, jitterMilliseconds: lat?.jitter, downloadMbps: down, uploadMbps: up, errors: errors)
    }
}

/// Collects `URLSessionTaskMetrics` for the last finished task.
final class MetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    struct Timing { var dnsMilliseconds: Double?; var responseMilliseconds: Double? }
    private let lock = NSLock()
    private var _last: Timing?
    var last: Timing? { lock.lock(); defer { lock.unlock() }; return _last }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let t = metrics.transactionMetrics.last else { return }
        var timing = Timing()
        if let a = t.domainLookupStartDate, let b = t.domainLookupEndDate { timing.dnsMilliseconds = b.timeIntervalSince(a) * 1000 }
        if let a = t.requestStartDate, let b = t.responseStartDate { timing.responseMilliseconds = b.timeIntervalSince(a) * 1000 }
        lock.lock(); _last = timing; lock.unlock()
    }
}

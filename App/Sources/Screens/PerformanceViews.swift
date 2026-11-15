import SwiftUI
import VitalsKit
import VitalsDesign

struct BenchmarkView: View {
    @Environment(AppModel.self) private var model
    @State private var running = false
    @State private var stage: BenchmarkRunner.Stage?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("About 5–10 seconds of CPU, graphics and storage work. It is skipped when the phone is hot: a hot phone only measures throttling.")
                    .font(.subheadline).foregroundStyle(VColor.ink2)
                Button { Task { await run() } } label: {
                    Text(running ? (stage?.label ?? "Starting…") : "Run benchmark").frame(maxWidth: .infinity)
                }
                .vitalsButton(.primary)
                .disabled(running || model.thermal.isHot)
                if model.thermal.isHot {
                    Label("The phone is \(model.thermal.label.lowercased()). Let it cool first.", systemImage: "thermometer.high").foregroundStyle(VColor.attention)
                }
                if let error { Text(error).foregroundStyle(VColor.attention) }
                if let b = model.benchmark { BenchmarkResultView(result: b) }
            }
            .padding(Space.l)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle("Benchmark")
    }

    func run() async {
        running = true
        error = nil
        defer { running = false; stage = nil }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let model = DeviceIdentity.modelIdentifier
        let injectedThermal = self.model.injected?.thermalLevel
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try BenchmarkRunner.run(thermal: { injectedThermal ?? ThermalLevel(ProcessInfo.processInfo.thermalState) },
                                        lowPowerMode: lowPower, modelIdentifier: model, cores: cores) { s in
                    Task { @MainActor in self.stage = s }
                }
            }.value
            await self.model.saveBenchmark(result)
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct BenchmarkResultView: View {
    let result: BenchmarkResult
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Last run · \(DayTimeFormatting.string(result.takenAt))")
            Panel {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(result.scores) { s in
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.label).foregroundStyle(VColor.ink)
                            Spacer()
                            Text(s.value.formatted(.number.precision(.fractionLength(0...1)))).font(VFont.numeral(.title3)).foregroundStyle(VColor.ink)
                            Text(s.unit).font(.caption).foregroundStyle(VColor.ink2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    HStack(spacing: 6) {
                        ProvenanceTag(.measured)
                        Text("\(result.totalSeconds.formatted(.number.precision(.fractionLength(1)))) s · heat \(result.thermalAtStart.label.lowercased()) → \(result.thermalAtEnd.label.lowercased())\(result.lowPowerMode ? " · Low Power Mode on" : "")")
                            .font(.caption2).foregroundStyle(VColor.ink2)
                    }
                }
            }
            Text(result.hasBaseline
                 ? "Compared with the expected range for this model."
                 : "No baseline for this model yet, so these are raw results. Vitals only compares against ranges measured on real phones.")
                .font(.caption).foregroundStyle(VColor.ink2)
        }
    }
}

struct NetworkTestView: View {
    @Environment(AppModel.self) private var model
    @State private var running = false
    @State private var stage: NetworkTester.Stage?
    @State private var confirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Measures DNS lookup, latency, download and upload against \(NetworkTestConfig.base.host() ?? "the test server"). It downloads about \(NetworkTestConfig.downloadBytes / 1_000_000) MB and uploads \(NetworkTestConfig.uploadBytes / 1_000_000) MB.")
                    .font(.subheadline).foregroundStyle(VColor.ink2)
                Button { confirm = true } label: {
                    Text(running ? "Testing \(stage?.rawValue ?? "")…" : "Start network test").frame(maxWidth: .infinity)
                }
                .vitalsButton(.primary).disabled(running)
                if let r = model.networkResult {
                    Panel {
                        VStack(alignment: .leading, spacing: Space.m) {
                            row("Download", r.downloadMbps, "Mbit/s")
                            row("Upload", r.uploadMbps, "Mbit/s")
                            row("Latency", r.latencyMilliseconds, "ms")
                            row("Jitter", r.jitterMilliseconds, "ms")
                            row("DNS lookup", r.dnsMilliseconds, "ms")
                            HStack(spacing: 6) {
                                ProvenanceTag(.measured)
                                Text("\(DayTimeFormatting.string(r.takenAt)) · \(r.interfaces) · \(r.endpoint)").font(.caption2).foregroundStyle(VColor.ink2)
                            }
                            ForEach(r.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(VColor.attention) }
                        }
                    }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle("Network test")
        .confirmationDialog("Use the network?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Start test") { Task { await run() } }
        } message: {
            Text("This sends requests to \(NetworkTestConfig.base.host() ?? "the test server") and uses about \((NetworkTestConfig.downloadBytes + NetworkTestConfig.uploadBytes) / 1_000_000) MB of data. Nothing about you or this phone is sent.")
        }
    }

    func row(_ label: String, _ value: Double?, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—").font(VFont.numeral(.title3))
                .accessibilityLabel(value == nil ? Text("not available") : Text(value!.formatted(.number.precision(.fractionLength(0...1)))))
            Text(unit).font(.caption).foregroundStyle(VColor.ink2)
        }
        .foregroundStyle(VColor.ink)
        .accessibilityElement(children: .combine)
    }

    func run() async {
        running = true
        defer { running = false; stage = nil }
        let interfaces = model.checkup?.readings.first { $0.id == "network.interfaces" }?.value.text ?? "unknown"
        let r = await NetworkTester.run(interfaces: interfaces) { s in Task { @MainActor in stage = s } }
        await model.saveNetworkResult(r)
    }
}

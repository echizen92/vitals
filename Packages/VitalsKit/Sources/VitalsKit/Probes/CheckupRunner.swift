import Foundation

/// Runs every on-device probe and reports each area the moment its probe really finishes,
/// so the scan animation follows real work rather than a timer.
public struct CheckupRunner: Sendable {
    public enum Event: Sendable {
        case areaStarted(Area)
        case areaFinished(Area, [Reading])
        case finished(Checkup)
    }

    public let source: any SystemSource
    public init(source: any SystemSource) { self.source = source }

    /// Reads one area.
    public func read(_ area: Area, at t: Date) async -> [Reading] {
        switch area {
        case .battery: return Probes.battery(await source.battery(), at: t)
        case .heat: return Probes.thermal(await source.thermal(), at: t)
        case .storage: return Probes.storage(await source.storage(), at: t)
        case .memory: return Probes.memory(await source.memory(), at: t)
        case .network: return Probes.network(await source.network(), at: t)
        case .software:
            var r = Probes.software(await source.software(), at: t)
            if let d = await source.display() { r += Probes.display(d, at: t) }
            return r
        }
    }

    /// Streams progress. `context` supplies history (samples, imports, benchmark) for the rules.
    public func run(now: Date = .now, context: @escaping @Sendable () async -> DiagnosisInput) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                var all: [Reading] = []
                // Probes run concurrently; each area is reported as soon as it is done.
                await withTaskGroup(of: (Area, [Reading]).self) { group in
                    for area in Area.allCases {
                        continuation.yield(.areaStarted(area))
                        group.addTask { (area, await self.read(area, at: now)) }
                    }
                    for await (area, readings) in group {
                        all += readings
                        continuation.yield(.areaFinished(area, readings))
                    }
                }
                var input = await context()
                input.readings = all
                input.now = now
                let results = DiagnosisEngine.evaluate(input)
                continuation.yield(.finished(Checkup(takenAt: now, results: results)))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs to completion without progress.
    public func runOnce(now: Date = .now, context: @escaping @Sendable () async -> DiagnosisInput) async -> Checkup {
        for await event in run(now: now, context: context) {
            if case .finished(let c) = event { return c }
        }
        return Checkup(takenAt: now, results: [])
    }

    /// One timeline sample from the current state.
    public func sample(source sampleSource: SampleSource, now: Date = .now) async -> Sample {
        let battery = await source.battery()
        return Sample(takenAt: now, thermal: await source.thermal(), batteryLevel: battery.level, charge: battery.state,
                      lowPowerMode: battery.lowPowerMode, source: sampleSource)
    }
}

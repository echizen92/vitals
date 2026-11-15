import Foundation
import Testing
@testable import VitalsKit

@Suite struct BenchmarkTests {
    @Test func refusesWhenHot() {
        #expect(throws: BenchmarkRunner.BenchError.self) {
            try BenchmarkRunner.run(thermal: { .serious }, lowPowerMode: false, modelIdentifier: "x", cores: 2, scale: 0.01) { _ in }
        }
    }

    @Test func smallRunProducesAllStagesWithoutBaseline() throws {
        var stages: [BenchmarkRunner.Stage] = []
        let r = try BenchmarkRunner.run(thermal: { .nominal }, lowPowerMode: false, modelIdentifier: "iPhone19,4", cores: 2, scale: 0.02) { stages.append($0) }
        #expect(stages == BenchmarkRunner.Stage.allCases)
        #expect(r.scores.map(\.id).contains("cpuSingle"))
        #expect(r.scores.allSatisfy { $0.value > 0 && $0.value.isFinite })
        #expect(!r.hasBaseline, "no invented baselines ship")
        #expect(r.verdict == nil)
    }

    @Test func cpuStageIsTimeBounded() {
        let (done, secs) = BenchmarkRunner.time { BenchmarkRunner.boundedCPU(total: Int.max / 2, cap: 0.2) }
        #expect(done > 0)
        #expect(secs < 1.0)
    }

    @Test func verdictAgainstBaseline() {
        let s = BenchmarkResult.Score(id: "cpuSingle", label: "x", value: 50, unit: "u", seconds: 1, expected: 100...200)
        #expect(s.verdict == .belowRange)
    }

    @Test func latencySummary() {
        let r = NetworkTester.summarize([10, 20, 30, 40])!
        #expect(r.median == 25)
        #expect(r.jitter == 10)
        #expect(NetworkTester.summarize([]) == nil)
        #expect(abs(NetworkTester.mbps(bytes: 1_250_000, seconds: 1) - 10) < 0.0001)
    }
}

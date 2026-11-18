import Foundation
import Testing
@testable import VitalsKit

@Suite struct HardwareModelTests {
    @Test func touchGridCompletes() {
        var g = TouchGrid(columns: 4, rows: 3)
        #expect(!g.complete)
        let first = g.paint(x: 1, y: 1, width: 400, height: 300)
        #expect(first)
        let again = g.paint(x: 2, y: 2, width: 400, height: 300)
        #expect(!again, "same cell twice is not new")
        for r in 0..<3 { for c in 0..<4 { g.paint(x: Double(c) * 100 + 50, y: Double(r) * 100 + 50, width: 400, height: 300) } }
        #expect(g.complete)
        #expect(g.missing.isEmpty)
        let outside = g.paint(x: 400, y: 10, width: 400, height: 300)
        #expect(!outside, "out of bounds ignored")
    }

    @Test func fastDragPaintsEveryCellOnTheWay() {
        var g = TouchGrid(columns: 8, rows: 2)
        let n = g.paintLine(from: (5, 5), to: (795, 5), width: 800, height: 200)
        #expect(n == 8)
        #expect((0..<8).allSatisfy { g.isPainted(column: $0, row: 0) })
    }

    @Test func suiteDependsOnDuo() {
        #expect(HardwareTestKind.suite(isDuo: true).contains(.hinge))
        #expect(!HardwareTestKind.suite(isDuo: false).contains(.hinge))
        #expect(!HardwareTestKind.suite(isDuo: false).contains(.duoDisplays))
    }

    @Test func signalActivity() {
        var s = SignalActivity(threshold: 0.05)
        for _ in 0..<20 { s.add(0.98) }
        #expect(!s.everLive, "a stuck sensor is not live")
        s.add(1.2)
        #expect(s.everLive)
        s.add(.nan)
        #expect(s.count == 21)
    }

    @Test func toneHasFadesAndLength() {
        let t = ToneGenerator.samples(frequency: 440, seconds: 0.5)
        #expect(t.count == 22_050)
        #expect(abs(t[0]) < 0.001)
        #expect(t.map { abs($0) }.max()! <= 0.5)
    }

    @Test func resultsRoundTrip() throws {
        let r = [HardwareTestResult(kind: .gps, outcome: .passed, details: ["±5 m"], testedAt: t0)]
        #expect(try JSON.decode([HardwareTestResult].self, JSON.encode(r)) == r)
    }
}

@Suite struct DropCheckTests {
    @Test func planCoversEveryTestOnce() {
        #expect(Set(DropCheck.order) == Set(HardwareTestKind.allCases))
        #expect(DropCheck.order.count == HardwareTestKind.allCases.count)
        #expect(DropCheck.plan(isDuo: false) == HardwareTestKind.suite(isDuo: false).sorted { DropCheck.order.firstIndex(of: $0)! < DropCheck.order.firstIndex(of: $1)! })
        #expect(DropCheck.plan(isDuo: true).contains(.hinge))
        #expect(!DropCheck.plan(isDuo: false).contains(.hinge))
        #expect(DropCheck.plan(isDuo: false).first == .display)
    }

    @Test func summaryIgnoresResultsFromBeforeTheRun() {
        let start = Date(timeIntervalSince1970: 1_000)
        let plan: [HardwareTestKind] = [.display, .touch, .cameras, .speakers]
        let results = [
            HardwareTestResult(kind: .display, outcome: .passed, testedAt: start.addingTimeInterval(5)),
            HardwareTestResult(kind: .touch, outcome: .passed, testedAt: start.addingTimeInterval(-60)),   // old: not this run
            HardwareTestResult(kind: .cameras, outcome: .failed, testedAt: start.addingTimeInterval(30)),
            HardwareTestResult(kind: .speakers, outcome: .skipped, testedAt: start.addingTimeInterval(40)),
        ]
        let s = DropCheck.summarize(plan: plan, results: results, since: start)
        #expect(s.passed == [.display])
        #expect(s.failed == [.cameras])
        #expect(s.notChecked == [.touch, .speakers])
        #expect(s.verdict == .damageFound)
    }

    @Test func introAndStepsCountTheSameSteps() {
        // The check-up is a step too: 15 tests + 1 on a regular iPhone, 17 + 1 on the Duo.
        #expect(DropCheck.stepCount(isDuo: false) == DropCheck.plan(isDuo: false).count + 1)
        #expect(DropCheck.stepCount(isDuo: true) == HardwareTestKind.allCases.count + 1)
        #expect(DropCheck.stepCount(isDuo: false) == 16)
        #expect(DropCheck.stepCount(isDuo: true) == 18)
    }

    @Test func failedLineFollowsTheCount() {
        #expect(DropCheck.Summary(failed: [.touch]).failedLine == "This did not pass.")
        #expect(DropCheck.Summary(failed: [.touch, .cameras]).failedLine == "These did not pass.")
    }

    @Test func privacyLineOnlyForCameraAndMicrophone() {
        #expect(HardwareTestKind.allCases.filter(\.usesCameraOrMicrophone) == [.microphones, .cameras])
    }

    @Test func verdicts() {
        #expect(DropCheck.Summary(passed: [.display]).verdict == .allPassed)
        #expect(DropCheck.Summary(passed: [.display], notChecked: [.nfc]).verdict == .passedWithGaps)
        #expect(DropCheck.Summary(notChecked: [.nfc]).verdict == .notChecked)
    }
}

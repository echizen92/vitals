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

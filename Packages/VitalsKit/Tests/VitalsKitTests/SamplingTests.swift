import Foundation
import Testing
@testable import VitalsKit

func sample(_ minutes: Double, _ thermal: ThermalLevel, battery: Double? = nil, charge: ChargeState = .unplugged) -> Sample {
    Sample(takenAt: t0.addingTimeInterval(minutes * 60), thermal: thermal, batteryLevel: battery, charge: charge, lowPowerMode: false, source: .fixture)
}

@Suite struct HotSpellTests {
    @Test func noSamplesNoSpells() {
        #expect(HotSpellDetector.detect([]).isEmpty)
    }

    @Test func groupsConsecutiveHotSamples() {
        let s = [sample(0, .nominal), sample(10, .serious, battery: 0.80), sample(20, .critical, battery: 0.76), sample(30, .serious, battery: 0.72),
                 sample(40, .fair), sample(50, .serious), sample(60, .nominal)]
        let spells = HotSpellDetector.detect(s)
        #expect(spells.count == 2)
        #expect(spells[0].peak == .critical)
        #expect(spells[0].sampleCount == 3)
        #expect(spells[0].duration == 20 * 60)
        // 8 points over 20 minutes = 24 %/h.
        #expect(abs((spells[0].drainPerHour ?? 0) - 24) < 0.001)
        #expect(spells[1].sampleCount == 1)
        #expect(!spells[1].ongoing)
    }

    @Test func gapSplitsSpell() {
        let s = [sample(0, .serious), sample(10, .serious), sample(120, .serious)]
        #expect(HotSpellDetector.detect(s).count == 2)
    }

    @Test func chargingSpellHasNoDrain() {
        let s = [sample(0, .serious, battery: 0.5, charge: .charging), sample(30, .serious, battery: 0.6, charge: .charging)]
        let spell = HotSpellDetector.detect(s)[0]
        #expect(spell.wasCharging)
        #expect(spell.drainPerHour == nil)
        #expect(spell.ongoing)
    }

    @Test func unsortedInputIsSorted() {
        let s = [sample(20, .serious), sample(0, .serious), sample(10, .serious)]
        let spell = HotSpellDetector.detect(s)[0]
        #expect(spell.start == t0)
        #expect(spell.sampleCount == 3)
    }
}

@Suite struct BatteryMathTests {
    @Test func drainOverOnBatteryRun() {
        let s = [sample(-120, .nominal, battery: 0.90), sample(-60, .nominal, battery: 0.80), sample(0, .nominal, battery: 0.70)]
        #expect(abs((BatteryMath.drainPerHour(s, now: t0) ?? 0) - 10) < 0.001)
    }

    @Test func shortSpanGivesNoRate() {
        let s = [sample(-2, .nominal, battery: 0.90), sample(0, .nominal, battery: 0.85)]
        #expect(BatteryMath.drainPerHour(s, now: t0) == nil)
    }

    @Test func chargingSegmentsIgnoredForDrain() {
        let s = [sample(-120, .nominal, battery: 0.50, charge: .charging), sample(-60, .nominal, battery: 0.80, charge: .charging),
                 sample(-40, .nominal, battery: 0.80), sample(0, .nominal, battery: 0.76)]
        #expect(abs((BatteryMath.drainPerHour(s, now: t0) ?? 0) - 6) < 0.001)
        #expect(abs((BatteryMath.chargePerHour(s, now: t0) ?? 0) - 30) < 0.001)
    }

    @Test func coverage() {
        let s = [sample(-30, .nominal), sample(-90, .nominal), sample(-95, .nominal)]
        let c = Coverage.of(s, from: t0.addingTimeInterval(-4 * 3600), to: t0)
        #expect(c.sampleCount == 3)
        #expect(c.fraction == 0.5)
    }
}

@Suite(.serialized) struct StoreTests {
    func tempStore() throws -> VitalsStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try VitalsStore(url: dir.appendingPathComponent("t.sqlite"))
    }

    @Test func samplesRoundTrip() async throws {
        let store = try tempStore()
        let s = [sample(0, .serious, battery: 0.5), sample(10, .nominal, battery: nil, charge: .charging)]
        try await store.insert(s)
        let back = try await store.samples(from: t0.addingTimeInterval(-60))
        #expect(back == s)
        try await store.pruneSamples(olderThan: 0, now: t0.addingTimeInterval(5 * 60))
        #expect(try await store.sampleCount() == 1)
    }

    @Test func importsAndEvents() async throws {
        let store = try tempStore()
        let rec = ImportRecord(id: "a", fileName: "x.ips", kind: .crash, importedAt: t0, coversDate: t0, byteSize: 10, storedPath: nil, eventCount: 1, notes: [])
        let ev = LogEvent(id: "e", kind: .crash, process: "Maps", timestamp: t0, importID: "a")
        try await store.save(rec, events: [ev])
        #expect(try await store.imports() == [rec])
        #expect(try await store.events() == [ev])
        try await store.deleteImport(id: "a")
        #expect(try await store.events().isEmpty)
    }

    @Test func docs() async throws {
        let store = try tempStore()
        let h = BatteryHealth(maxCapacityPercent: 90, cycleCount: 100, designCapacity: nil, fullChargeCapacity: nil, asOf: t0, sourceFile: "f", keysUsed: [])
        try await store.put(h, key: DocKey.batteryHealth)
        #expect(try await store.get(BatteryHealth.self, key: DocKey.batteryHealth) == h)
    }
}

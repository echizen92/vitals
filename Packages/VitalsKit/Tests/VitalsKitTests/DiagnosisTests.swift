import Foundation
import Testing
@testable import VitalsKit

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func readings(_ s: FixedSystemSource, at t: Date = t0) async -> [Reading] {
    let runner = CheckupRunner(source: s)
    var all: [Reading] = []
    for a in Area.allCases { all += await runner.read(a, at: t) }
    return all
}

@Suite struct ProbeTests {
    @Test func everyReadingHasProvenanceAndSource() async {
        let r = await readings(.healthy)
        #expect(!r.isEmpty)
        for reading in r {
            #expect(!reading.source.isEmpty, "\(reading.id) has no source")
        }
        #expect(Set(r.map(\.id)).count == r.count, "reading ids must be unique")
    }

    @Test func batteryLevelMissingOnSimulatorIsNotInvented() {
        let r = Probes.battery(BatteryRaw(level: nil, state: .unknown, lowPowerMode: false), at: t0)
        #expect(r.first { $0.id == "battery.level" } == nil)
    }

    @Test func storageUsedIsInferred() {
        let r = Probes.storage(FixedSystemSource.healthy.storageRaw, at: t0)
        #expect(r.first { $0.id == "storage.used" }?.provenance == .inferred)
        #expect(r.first { $0.id == "storage.free" }?.provenance == .measured)
    }

    @Test func modelNameFromBundledTable() {
        #expect(Catalog.modelName(for: "iPhone19,4") == "iPhone Duo")
        #expect(Catalog.isDuo("iPhone19,4"))
        #expect(!Catalog.isDuo("iPhone18,1"))
    }

    @Test func versionCompare() {
        #expect(compareVersions("27.1", "27.2") == .orderedAscending)
        #expect(compareVersions("27.10", "27.9") == .orderedDescending)
        #expect(compareVersions("27.2", "27.2.0") == .orderedSame)
    }

    @Test func runnerReportsEveryAreaThenFinishes() async {
        var finished: [Area] = []
        var checkup: Checkup?
        for await e in CheckupRunner(source: FixedSystemSource.healthy).run(now: t0, context: { DiagnosisInput(readings: []) }) {
            switch e {
            case .areaFinished(let a, _): finished.append(a)
            case .finished(let c): checkup = c
            case .areaStarted: break
            }
        }
        #expect(Set(finished) == Set(Area.allCases))
        #expect(checkup?.results.count == Area.allCases.count)
    }
}

@Suite struct DiagnosisRuleTests {
    func evaluate(_ s: FixedSystemSource, samples: [Sample] = [], health: BatteryHealth? = nil, events: [LogEvent] = []) async -> [Area: AreaResult] {
        let input = DiagnosisInput(readings: await readings(s), samples: samples, batteryHealth: health, logEvents: events, now: t0)
        return Dictionary(uniqueKeysWithValues: DiagnosisEngine.evaluate(input).map { ($0.area, $0) })
    }

    @Test func healthyPhoneIsGoodWhereMeasurable() async {
        var s = FixedSystemSource.healthy
        s.softwareRaw.osVersion = Catalog.latestOS ?? "27.2"
        let r = await evaluate(s)
        #expect(r[.storage]?.status == .good)
        #expect(r[.network]?.status == .good)
        #expect(r[.heat]?.status == .good)
        #expect(r[.software]?.status == .good)
        #expect(r[.battery]?.status == .good)
        #expect(r[.battery]?.sentence.contains("Battery Health") == true, "wear is not readable and the sentence says where it is")
    }

    @Test func noBatteryDataIsUnknownNotGood() async {
        var s = FixedSystemSource.healthy
        s.batteryRaw = BatteryRaw(level: nil, state: .unknown, lowPowerMode: false)
        let r = await evaluate(s)
        #expect(r[.battery]?.status == .unknown)
    }

    @Test func seriousThermalIsAProblem() async {
        var s = FixedSystemSource.healthy
        s.thermalLevel = .serious
        let r = await evaluate(s)
        #expect(r[.heat]?.status == .problem)
        #expect(r[.heat]?.findings.first?.evidence.first?.provenance == .measured)
    }

    @Test func fairThermalIsAttention() async {
        var s = FixedSystemSource.healthy
        s.thermalLevel = .fair
        #expect(await evaluate(s)[.heat]?.status == .attention)
    }

    @Test func storageThresholds() async {
        var s = FixedSystemSource.healthy
        s.storageRaw = StorageRaw(total: 128_000_000_000, free: 1_000_000_000, freeForImportant: 2_000_000_000, freeForOpportunistic: nil)
        #expect(await evaluate(s)[.storage]?.status == .problem)
        s.storageRaw = StorageRaw(total: 128_000_000_000, free: 6_000_000_000, freeForImportant: 7_000_000_000, freeForOpportunistic: nil)
        #expect(await evaluate(s)[.storage]?.status == .attention)
        // A big drive with 15 GB free (under 5%) is worth a look, not a problem.
        s.storageRaw = StorageRaw(total: 494_000_000_000, free: 15_000_000_000, freeForImportant: 15_000_000_000, freeForOpportunistic: nil)
        #expect(await evaluate(s)[.storage]?.status == .attention)
        s.storageRaw = StorageRaw(total: 1_000_000_000_000, free: 60_000_000_000, freeForImportant: 60_000_000_000, freeForOpportunistic: nil)
        #expect(await evaluate(s)[.storage]?.status == .good)
    }

    @Test func wornBatteryFromImport() async {
        let health = BatteryHealth(maxCapacityPercent: 76, cycleCount: 912, designCapacity: nil, fullChargeCapacity: nil,
                                   asOf: t0, sourceFile: "Analytics-test.ips.ca.synced", keysUsed: ["x"])
        let r = await evaluate(.healthy, health: health)
        #expect(r[.battery]?.status == .problem)
        #expect(r[.battery]?.readings.first { $0.id == "battery.maxCapacity" }?.provenance == .parsedFromLog)
        #expect(r[.battery]?.readings.first { $0.id == "battery.maxCapacity" }?.unverified == true)
        #expect(r[.battery]?.findings.contains { $0.id == "battery.cycles" } == true)
    }

    @Test func capacityWorkedOutFromMahIsInferred() {
        let h = BatteryHealth(maxCapacityPercent: nil, cycleCount: nil, designCapacity: 4000, fullChargeCapacity: 3400, asOf: t0, sourceFile: "f", keysUsed: [])
        #expect(h.effectiveMaxCapacity?.value == 85)
        #expect(h.effectiveMaxCapacity?.provenance == .inferred)
    }

    @Test func offlineIsProblem() async {
        var s = FixedSystemSource.healthy
        s.networkRaw.status = .unsatisfied
        #expect(await evaluate(s)[.network]?.status == .problem)
    }

    @Test func oldOSIsAttention() async {
        var s = FixedSystemSource.healthy
        s.softwareRaw.osVersion = "26.0"
        let r = await evaluate(s)
        #expect(r[.software]?.status == .attention)
    }

    @Test func frequentCrashesAndPanics() async {
        var events = (0..<5).map { LogEvent(id: "c\($0)", kind: .crash, process: "Photos", timestamp: t0.addingTimeInterval(Double(-$0) * 3600), importID: "i") }
        events.append(LogEvent(id: "p", kind: .panic, process: "kernel", timestamp: t0.addingTimeInterval(-100), importID: "p"))
        var s = FixedSystemSource.healthy
        s.softwareRaw.osVersion = Catalog.latestOS ?? "27.2"
        let r = await evaluate(s, events: events)
        #expect(r[.software]?.status == .problem)
        #expect(r[.software]?.findings.contains { $0.summary.contains("Photos crashed 5 times") } == true)
    }

    @Test func hotSpellsRaiseHeat() async {
        let samples = (0..<6).map { i in
            Sample(takenAt: t0.addingTimeInterval(Double(-i) * 600), thermal: i < 4 ? .serious : .nominal, batteryLevel: 0.5 + Double(i) * 0.02,
                   charge: .unplugged, lowPowerMode: false, source: .fixture)
        }
        let r = await evaluate(.healthy, samples: samples)
        #expect(r[.heat]?.findings.contains { $0.id == "heat.spells" } == true)
    }
}

@Suite struct OSTableDateTests {
    @Test func dateReadsAsDayAndShortMonth() {
        #expect(Catalog.dayMonth(isoDay: "2026-11-15", locale: Locale(identifier: "en_GB")) == "15 Nov")
        #expect(Catalog.dayMonth(isoDay: "2026-11-15", locale: Locale(identifier: "en_US")) == "Nov 15")
        #expect(Catalog.dayMonth(isoDay: "not a date") == nil)
        #expect(!(Catalog.osTableDateText ?? "").contains("-"), "never the raw ISO date")
    }
}

import Foundation
import Testing
@testable import VitalsKit

func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
}

func importFixture(_ name: String) throws -> ImportResult {
    try LogImporter.importFile(at: fixture(name), id: name, now: t0)
}

@Suite struct ImportTests {
    @Test func sniffsEveryFixture() {
        #expect(LogImporter.sniff(url: fixture("Photos-2027-01-15-075510.ips")) == .crash)
        #expect(LogImporter.sniff(url: fixture("JetsamEvent-2027-01-15-074002.ips")) == .jetsam)
        #expect(LogImporter.sniff(url: fixture("mediaanalysisd.cpu_resource-2027-01-15-074530.ips")) == .cpuResource)
        #expect(LogImporter.sniff(url: fixture("locationd.wakeups_resource-2027-01-15-075000.ips")) == .wakeups)
        #expect(LogImporter.sniff(url: fixture("Maps-hang-2027-01-14-120000.ips")) == .hang)
        #expect(LogImporter.sniff(url: fixture("panic-full-2027-01-13-220000.ips")) == .panic)
        #expect(LogImporter.sniff(url: fixture("Analytics-2027-01-15-001000.ips.ca.synced")) == .analytics)
        #expect(LogImporter.sniff(url: fixture("sysdiagnose_2027.01.15_synthetic.tar.gz")) == .sysdiagnose)
        #expect(LogImporter.sniff(url: fixture("README.md")) == .unknown)
    }

    @Test func classifyFallsBackToBugTypeThenBody() {
        let h = IPSParser.header(from: #"{"bug_type":"309","name":"Notes"}"#)
        #expect(IPSParser.classify(fileName: "renamed.ips", header: h, body: "{}") == .crash)
        #expect(IPSParser.classify(fileName: "x.ips", header: nil, body: "{\"largestProcess\":\"a\"}") == .jetsam)
    }

    @Test func crash() throws {
        let r = try importFixture("Photos-2027-01-15-075510.ips")
        #expect(r.events.count == 1)
        let e = r.events[0]
        #expect(e.kind == .crash)
        #expect(e.process == "Photos")
        #expect(e.bundleID == "com.apple.mobileslideshow")
        #expect(e.detail?.contains("EXC_BAD_ACCESS") == true)
        #expect(e.timestamp == IPSDate.parse("2027-01-15 07:55:10.42 +0000"))
        #expect(r.record.eventCount == 1)
    }

    @Test func jetsam() throws {
        let r = try importFixture("JetsamEvent-2027-01-15-074002.ips")
        let killed = r.events.filter { $0.kind == .jetsam }
        #expect(killed.map(\.process) == ["Safari"])
        #expect(killed[0].detail == "vm-pageshortage")
        let largest = r.events.first { $0.kind == .jetsamLargest }
        #expect(largest?.process == "mediaanalysisd")
        // 120000 pages × 16 KB = 1875 MB
        #expect(abs((largest?.magnitude ?? 0) - 1875) < 0.5)
    }

    @Test func cpuResource() throws {
        let r = try importFixture("mediaanalysisd.cpu_resource-2027-01-15-074530.ips")
        let e = try #require(r.events.first)
        #expect(e.kind == .cpuResource)
        #expect(e.process == "mediaanalysisd")
        #expect(e.magnitude == 150)
        #expect(e.detail == "used 150 s of CPU in 180 s")
        #expect(r.record.notes.contains { $0.contains("unverified") })
    }

    @Test func wakeupsAndHangAndPanic() throws {
        #expect(try importFixture("locationd.wakeups_resource-2027-01-15-075000.ips").events.first?.magnitude == 45001)
        let hang = try importFixture("Maps-hang-2027-01-14-120000.ips").events.first
        #expect(hang?.kind == .hang)
        #expect(hang?.process == "Maps")
        #expect(hang?.detail == "hung for 6.20s")
        let panic = try importFixture("panic-full-2027-01-13-220000.ips").events.first
        #expect(panic?.kind == .panic)
        #expect(panic?.detail?.contains("thermalmonitord") == true)
    }

    @Test func analyticsBatteryKeys() throws {
        let r = try importFixture("Analytics-2027-01-15-001000.ips.ca.synced")
        // This early synthetic file predates the real record names; only an explicit percent key is used.
        let h = try #require(r.batteryHealth)
        #expect(h.maxCapacityPercent == 87)
        #expect(h.asOf == IPSDate.parse("2027-01-15 00:10:00.00 +0000"))
        // Records with "thermal" in the name have no timestamps; they are not turned into timed events.
        #expect(!r.events.contains { $0.kind == .thermal })
    }

    @Test func analyticsWithoutKeysSaysSoAndInventsNothing() throws {
        let r = try importFixture("Analytics-2027-01-14-001000.nokeys.ips.ca.synced")
        #expect(r.batteryHealth == nil)
        #expect(r.record.notes.contains { $0.contains("Maximum capacity is not in this file") })
    }

    @Test func analyticsNeverDerivesCapacityFromLooseKeys() throws {
        // Confirmed on the Duo: capacity is not in the daily file. Loose mAh-looking keys are ignored.
        #expect(try importFixture("Analytics-2027-01-13-001000.mah.ips.ca.synced").batteryHealth == nil)
    }

    @Test func analyticsDateFromName() {
        let d = AnalyticsParser.dateFromFileName("Analytics-2026-11-14-093012.ips.ca.synced")
        #expect(d != nil)
        #expect(Calendar.current.component(.hour, from: d!) == 9)
    }

    @Test func sysdiagnoseStreamsAndFindsReports() throws {
        var fractions: [Double] = []
        let r = try LogImporter.importFile(at: fixture("sysdiagnose_2027.01.15_synthetic.tar.gz"), id: "sd", now: t0) { fractions.append($0) }
        #expect(r.record.kind == .sysdiagnose)
        #expect(r.extractedFiles.count == 5)
        #expect(r.extractedFiles.contains { $0.name.hasSuffix("longpath-entry.ips") }, "long tar paths must be read")
        #expect(r.events.contains { $0.kind == .crash && $0.process == "Photos" })
        #expect(r.events.contains { $0.kind == .cpuResource && $0.process == "mediaanalysisd" })
        #expect(r.batteryHealth?.maxCapacityPercent == 87)
        #expect(Set(r.events.map(\.id)).count == r.events.count, "event ids unique across the archive")
        #expect(fractions.last ?? 0 > 0.99)
    }

    @Test func notGzipThrows() {
        #expect(throws: (any Error).self) {
            try TarGzReader(url: fixture("README.md")).read(want: { _ in true }, found: { _, _ in })
        }
    }

    @Test func stableIDs() {
        #expect(LogImporter.stableID(name: "a", size: 1) == LogImporter.stableID(name: "a", size: 1))
        #expect(LogImporter.stableID(name: "a", size: 1) != LogImporter.stableID(name: "a", size: 2))
    }
}

@Suite struct CorrelationTests {
    func allEvents() throws -> [LogEvent] {
        try ["Photos-2027-01-15-075510.ips", "JetsamEvent-2027-01-15-074002.ips", "mediaanalysisd.cpu_resource-2027-01-15-074530.ips",
             "Instagram.cpu_resource-2027-01-15-075800.ips", "locationd.wakeups_resource-2027-01-15-075000.ips",
             "Maps-hang-2027-01-14-120000.ips", "panic-full-2027-01-13-220000.ips"].flatMap { try importFixture($0).events }
    }

    @Test func ranksCPUHeavyProcessFirst() throws {
        let spell = HotSpell(start: IPSDate.parse("2027-01-15 07:42:00.00 +0000")!, end: IPSDate.parse("2027-01-15 07:56:00.00 +0000")!,
                             peak: .serious, drainPerHour: 20, wasCharging: false, sampleCount: 5, ongoing: false)
        let c = Correlator.culprits(for: spell, events: try allEvents())
        #expect(c.first?.process == "mediaanalysisd", "150 CPU s inside the spell plus largest memory user")
        #expect(c.first?.score == 1)
        #expect(c.contains { $0.process == "Instagram" })
        #expect(!c.contains { $0.process == "Maps" }, "a hang the day before is not evidence")
        #expect(!c.contains { $0.process == "kernel" }, "panics are not heat culprits")
        let insta = c.first { $0.process == "Instagram" }!
        let locd = c.first { $0.process == "locationd" }!
        #expect(insta.rawScore > 0 && locd.rawScore > 0)
    }

    @Test func nothingNearbyMeansNoCulprits() throws {
        let spell = HotSpell(start: t0.addingTimeInterval(86_400), end: t0.addingTimeInterval(90_000), peak: .serious, drainPerHour: nil,
                             wasCharging: true, sampleCount: 2, ongoing: false)
        #expect(Correlator.culprits(for: spell, events: try allEvents()).isEmpty)
    }

    @Test func crashSummary() throws {
        var events = try allEvents()
        events.append(LogEvent(id: "x", kind: .crash, process: "Photos", timestamp: t0, importID: "i"))
        let s = CrashSummary.build(from: events)
        #expect(s.first?.process == "Photos")
        #expect(s.first?.crashes == 2)
        #expect(s.contains { $0.process == "Maps" && $0.hangs == 1 })
    }
}

@Suite struct CompanionImportTests {
    @Test func importsSimulatedCaptureFromThePythonEngine() throws {
        let r = try importFixture("simulated.vitalscapture")
        #expect(r.record.kind == .companionCapture)
        #expect(r.samples.count >= 5)
        #expect(r.samples.allSatisfy { $0.thermalUnknown && $0.temperatureC != nil && $0.source == .companion })
        #expect(r.processSamples.count > 10)
        #expect(r.events.contains { $0.kind == .liveCPU && $0.process == "mediaanalysisd" })
        #expect(!r.events.contains { $0.process == "SpringBoard" }, "below 20% CPU is not an event")
        #expect(r.record.notes.contains { $0.contains("SIMULATED") })
        #expect(r.record.notes.contains { $0.contains("temperature only") })
        // Write rates from two snapshots, overhead processes left out, and per-process totals.
        let bird = try #require(r.processRates.first { $0.process == "bird" })
        #expect(abs(bird.bytesWrittenPerMinute / 1e6 - 230) < 5)
        #expect(!r.processRates.contains { ["sysmond", "DTServiceHub", "remotepairingdeviced"].contains($0.process) })
        #expect(r.processTotals.contains { $0.process == "cloudd" && $0.bytesWritten > 100e9 })
    }

    @Test func companionRatesFeedTheCase() throws {
        let r = try importFixture("simulated.vitalscapture")
        let input = CaseInput(facts: [UserFact(key: .icloudDriveGB, value: 40, enteredAt: .now)], rates: r.processRates,
                              totals: r.processTotals, now: .now)
        let result = CaseEngine.evaluate(input)
        #expect(result.hypotheses.contains { $0.id == "icloud.stuckSync" })
    }

    @Test func temperatureOnlySamplesNeverMakeHotSpells() {
        let s = (0..<5).map { Sample(takenAt: t0.addingTimeInterval(Double($0) * 60), thermal: .critical, batteryLevel: nil, charge: .unknown,
                                     lowPowerMode: false, source: .companion, temperatureC: 45, thermalUnknown: true) }
        #expect(HotSpellDetector.detect(s).isEmpty)
    }

    @Test func storeKeepsThermalUnknown() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try VitalsStore(url: dir.appendingPathComponent("t.sqlite"))
        let s = Sample(takenAt: t0, thermal: .nominal, batteryLevel: 0.5, charge: .unplugged, lowPowerMode: false, source: .companion, temperatureC: 38.2, thermalUnknown: true)
        try await store.insert(s)
        #expect(try await store.samples(from: t0.addingTimeInterval(-1)) == [s])
    }
}

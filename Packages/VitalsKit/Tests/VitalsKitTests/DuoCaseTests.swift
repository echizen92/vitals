import Foundation
import Testing
@testable import VitalsKit

/// The first real diagnosis (iPhone Duo, 15 Nov 2026) as an end-to-end regression (plan §4a item 10, §4b, §4c).
/// Fixtures are synthetic and redacted, built by Fixtures/duo-case/make.py from the real record names.
@Suite struct DuoCaseTests {
    static let sgt = TimeZone(identifier: "Asia/Singapore")!
    static func date(_ s: String) -> Date { IPSDate.parse(s)! }
    static let morning1 = date("2026-11-15 10:45:00.00 +0800")
    static let morning2 = date("2026-11-16 10:00:00.00 +0800")

    func load(_ names: [String], now: Date) throws -> (days: [AnalyticsDay], events: [LogEvent]) {
        var days: [AnalyticsDay] = [], events: [LogEvent] = []
        for n in names {
            let r = try LogImporter.importFile(at: fixture("duo-case/\(n)"), id: n, now: now)
            days += r.analyticsDays
            events += r.events
        }
        return (days, events)
    }

    static let firstNight = ["Analytics-2026-11-15-080003.ips.ca.synced", "bird.diskwrites_resource-2026-11-15-004146.ips",
                             "StocksWidget.cpu_resource-2026-11-14-215449.ips", "ota_patch.txt"]

    // Live capture figures from REPORT.md (Mac + Developer Mode).
    static let liveRates = [
        ProcessRate(process: "bird", bytesWrittenPerMinute: 230e6, cpuPercent: 6, from: date("2026-11-15 11:00:00.00 +0800"), to: date("2026-11-15 11:05:00.00 +0800")),
        ProcessRate(process: "cloudd", bytesWrittenPerMinute: 227e6, cpuPercent: 18.5, from: date("2026-11-15 11:00:00.00 +0800"), to: date("2026-11-15 11:05:00.00 +0800")),
        ProcessRate(process: "nsurlsessiond", bytesWrittenPerMinute: 8e6, cpuPercent: 13, from: date("2026-11-15 11:00:00.00 +0800"), to: date("2026-11-15 11:05:00.00 +0800")),
    ]
    static let liveTotals = [
        ProcessTotal(process: "bird", bytesWritten: 103.6e9, since: date("2026-11-15 02:01:00.00 +0800"), at: date("2026-11-15 11:05:00.00 +0800")),
        ProcessTotal(process: "cloudd", bytesWritten: 116.9e9, since: date("2026-11-15 02:01:00.00 +0800"), at: date("2026-11-15 11:05:00.00 +0800")),
    ]
    static let driveUnder50 = UserFact(key: .icloudDriveGB, value: 50, enteredAt: date("2026-11-15 11:06:00.00 +0800"))

    @Test func parsesTheRealRecordNames() throws {
        let (days, events) = try load(Self.firstNight, now: Self.morning1)
        let d = try #require(days.first)
        #expect(d.cycleCount == 1)
        #expect(d.setupDataSource == "iCloud")
        #expect(d.fromFactory == true)
        #expect(d.successfulInstalls == 92)
        #expect(d.thermalPressureSeconds["Light"] == 7056)
        #expect(d.thermalPressureSeconds["Moderate"] == 4839)
        #expect(d.watchdogResets == 1 || d.watchdogResets == 2)
        #expect(d.healthRestoreUnfinished == true)
        #expect(d.healthDBSizeNoUnit == 600)
        #expect(d.bytesWritten(process: "cloudd") == 58e9)
        #expect(d.spotlightRebuilds == 2)
        #expect(d.batteryLevels == [24, 17])
        // Maximum capacity is never invented from this file.
        let health = try LogImporter.importFile(at: fixture("duo-case/Analytics-2026-11-15-080003.ips.ca.synced"), id: "a", now: Self.morning1).batteryHealth
        #expect(health?.cycleCount == 1)
        #expect(health?.effectiveMaxCapacity == nil)
        // Day-precision events are marked as such; report events keep their minute.
        #expect(events.filter { $0.kind == .diskWrites && $0.isDayPrecision }.count >= 3)
        let bird = try #require(events.first { $0.kind == .diskWrites && !$0.isDayPrecision })
        #expect(bird.process == "bird")
        #expect(abs((bird.magnitude ?? 0) - 17.18) < 0.01)
        #expect(bird.detail?.contains("17.18 GB") == true || bird.detail?.contains("17.2 GB") == true)
        #expect(events.contains { $0.kind == .osUpdate })
        #expect(events.contains { $0.kind == .cpuResource && $0.process == "StocksWidget" })
    }

    @Test func stage1FirstNightIsExpectedTemporaryNotAFault() throws {
        let (days, events) = try load(Self.firstNight, now: Self.morning1)
        let c = CaseEngine.evaluate(CaseInput(days: days, events: events, now: Self.morning1))
        let primary = try #require(c.primary)
        #expect(primary.id == "context.newPhone")
        #expect(primary.status == .expected)
        #expect(primary.recheckAfter != nil, "re-check tomorrow")
        #expect(!c.hypotheses.contains { $0.id == "icloud.stuckSync" }, "first-night logs alone do not justify 'stuck'")
        #expect(!c.hypotheses.contains { $0.status == .problem })
        // The harmless fix is offered on day one, with the caveat that the load may be normal.
        #expect(primary.summary.contains("restart is harmless"))
        #expect(AdviceCatalog.entry(for: primary.adviceKey)?.actions.contains("guided.restart") == true)
        // The watchdog reset is recorded, but not as a fault during setup.
        let restart = c.hypotheses.first { $0.id == "restart.unexpected" }
        #expect(restart?.status == .expected)
        #expect(c.couldNotDetermine.contains { $0.contains("Settings > Battery") })

        // And the scorecard shows Heat as expected, not as a problem.
        var input = DiagnosisInput(readings: Probes.thermal(.nominal, at: Self.morning1), samples: hotNight(), logEvents: events, caseResult: c, now: Self.morning1)
        input.readings += Probes.battery(BatteryRaw(level: 0.77, state: .unplugged, lowPowerMode: false), at: Self.morning1)
        let heat = DiagnosisEngine.evaluate(.heat, input)
        #expect(heat.status == .expected)
        #expect(heat.couldNotDetermine?.isEmpty == false)
    }

    @Test func stage2LiveCaptureAndOneFactRevisesToStuckSync() throws {
        let (days, events) = try load(Self.firstNight, now: Self.morning1)
        let first = CaseEngine.evaluate(CaseInput(days: days, events: events, now: Self.morning1))
        var record = CaseRecord(current: first)

        // Live figures without the fact: suspicious, asks the one question.
        let noFact = CaseEngine.evaluate(CaseInput(days: days, events: events, rates: Self.liveRates, totals: Self.liveTotals, now: Self.morning1))
        let s0 = try #require(noFact.hypotheses.first { $0.id == "icloud.stuckSync" })
        #expect(s0.asks == .icloudDriveGB)

        let second = CaseEngine.evaluate(CaseInput(days: days, events: events, facts: [Self.driveUnder50], rates: Self.liveRates,
                                                   totals: Self.liveTotals, now: Self.morning1.addingTimeInterval(1200)))
        let p = try #require(second.primary)
        #expect(p.id == "icloud.stuckSync")
        #expect(p.confidence == .likely, "inferred, not proven")
        #expect(p.status == .attention)
        #expect(p.tier == .macDeveloper)
        #expect(p.asks == nil)
        #expect(p.reasoning.contains { $0.provenance == .userSupplied })
        #expect(p.reasoning.contains { $0.text.contains("Not proven") })
        #expect(p.reasoning.contains { $0.text.contains("lockstep") })
        #expect(second.state == .actionSuggested)

        record = record.revised(with: second)
        #expect(record.history.first?.title.contains("new phone") == true, "the earlier verdict is kept")
        #expect(record.current.primary?.id == "icloud.stuckSync")
    }

    @Test func restartOutcomeSupportsTheHypothesisAndIsWatched() throws {
        let (days, events) = try load(Self.firstNight, now: Self.morning1)
        let t = Self.date("2026-11-15 11:04:00.00 +0800")
        let action = ActionRecord(actionID: "guided.restart", title: "Restart", findingID: "icloud.stuckSync", doneAt: t, watch: .syncWrites,
                                  before: MetricsSnapshot(takenAt: t, syncBytesPerMinute: 457e6),
                                  performedBy: "guided").evaluated(with: MetricsSnapshot(takenAt: t.addingTimeInterval(330), syncBytesPerMinute: 4.7e6))
        #expect(action.verdict == .improved)
        let c = CaseEngine.evaluate(CaseInput(days: days, events: events, facts: [Self.driveUnder50], rates: Self.liveRates,
                                              totals: Self.liveTotals, actions: [action], now: t.addingTimeInterval(400)))
        #expect(c.state == .resolvedWatching)
        let s = try #require(c.hypotheses.first { $0.id == "icloud.stuckSync" })
        #expect(s.reasoning.contains { $0.text.contains("After the restart") })
        #expect(s.status == .expected)
    }

    @Test func tier0PhoneOnlyReachesStuckSyncByDayTwo() throws {
        let names = Self.firstNight + ["Analytics-2026-11-16-080001.ips.ca.synced"]
        let (days, events) = try load(names, now: Self.morning2)
        #expect(days.count == 2)
        // Without the fact: a possible stuck sync, and the question.
        let a = CaseEngine.evaluate(CaseInput(days: days, events: events, now: Self.morning2))
        let s = try #require(a.hypotheses.first { $0.id == "icloud.stuckSync" })
        #expect(s.tier == .phoneOnly)
        #expect(s.asks == .icloudDriveGB)
        // With the one fact the phone cannot read: likely stuck sync, with restart as the advice.
        let b = CaseEngine.evaluate(CaseInput(days: days, events: events, facts: [Self.driveUnder50], now: Self.morning2))
        let p = try #require(b.primary)
        #expect(p.id == "icloud.stuckSync")
        #expect(p.confidence == .likely)
        #expect(p.tier == .phoneOnly)
        #expect(p.reasoning.contains { $0.text.contains("weaker than a live measurement") })
        #expect(AdviceCatalog.entry(for: p.adviceKey)?.actions.contains("guided.restart") == true)
        // Every finding says what the next tier would add.
        let f = DiagnosisEngine.finding(from: p)
        #expect(f.detail?.contains("Mac") == true)
        #expect(f.tier == .phoneOnly)
    }

    @Test func dayOverDayComparisonForTheRecheck() throws {
        let (days, _) = try load(["Analytics-2026-11-15-080003.ips.ca.synced", "Analytics-2026-11-16-080001.ips.ca.synced"], now: Self.morning2)
        let before = MetricsSnapshot(takenAt: Self.morning1, elevatedThermalSecondsDay: days[0].elevatedThermalSeconds, dayOf: days[0].date)
        let after = MetricsSnapshot(takenAt: Self.morning2, elevatedThermalSecondsDay: days[1].elevatedThermalSeconds, dayOf: days[1].date)
        let r = ActionRecord(actionID: "guided.recheckTomorrow", title: "Re-check", findingID: nil, doneAt: Self.morning1,
                             watch: .thermalPressureDay, before: before, performedBy: "guided").evaluated(with: after)
        #expect(r.verdict == .improved)
        #expect(r.outcomeText?.contains("fell") == true)
    }

    func hotNight() -> [Sample] {
        (0..<8).map { i in
            Sample(takenAt: Self.morning1.addingTimeInterval(Double(-i) * 1800), thermal: i < 4 ? .serious : .nominal, batteryLevel: 0.9 - Double(i) * 0.02,
                   charge: .unplugged, lowPowerMode: false, source: .app)
        }
    }
}

@Suite struct AdviceTests {
    /// Every finding the rules can produce maps to at least one action and an escalation (plan §5.14).
    @Test func everyFindingTypeHasActionsAndEscalation() {
        let keys = ["battery.low", "battery.fastDrain", "battery.worn", "battery.aging", "battery.cycles", "heat.now", "heat.spells",
                    "heat.cpuReports", "heat.unexplained", "heat.thermalShutdown", "storage.full", "storage.low", "memory.warnings",
                    "memory.cores", "memory.jetsam", "memory.benchmark", "network.none", "network.lowData", "network.vpn", "network.proxy",
                    "software.update", "software.uptime", "software.crash", "software.panic", "context.newPhone", "icloud.stuckSync",
                    "restart.unexpected", "restart.thermal"]
        for k in keys {
            let e = AdviceCatalog.entry(for: k)
            #expect(e != nil, "no advice for \(k)")
            #expect((e?.actions.count ?? 0) >= 1, "\(k) has no actions")
            let hasEscalation = !(e?.escalation.isEmpty ?? true) || ["network.lowData", "network.vpn", "software.update", "software.uptime"].contains(k)
            #expect(hasEscalation, "\(k) has no escalation")
            for id in (e?.actions ?? []) + (e?.escalation ?? []) { #expect(AdviceCatalog.action(id) != nil, "\(k) → missing action \(id)") }
        }
    }

    @Test func everyActionIsComplete() {
        for id in AdviceCatalog.allActionIDs {
            let a = AdviceCatalog.action(id)!
            #expect(!a.steps.isEmpty && !a.why.isEmpty && !a.downside.isEmpty, "\(id) incomplete")
        }
        #expect(AdviceCatalog.allActionIDs.count >= 25)
    }

    /// A person-started privacy check: present, honest about its limits, reachable from unexplained heat and drain.
    @Test func appPrivacyReportStep() {
        let a = AdviceCatalog.action("guided.appPrivacyReport")
        #expect(a?.steps.first?.contains("App Privacy Report") == true)
        #expect(a?.downside.contains("cannot show") == true)
        #expect(AdviceCatalog.escalation(for: "heat.unexplained").contains { $0.id == "guided.appPrivacyReport" })
        #expect(AdviceCatalog.escalation(for: "battery.fastDrain").contains { $0.id == "guided.appPrivacyReport" })
        #expect(AdviceCatalog.myth("sideChannel")?.hasPrefix("No app, Vitals included, can detect") == true)
    }

    /// Photo clean-up is not judged until Recently Deleted is emptied.
    @Test func photoCleanupWaitsForRecentlyDeleted() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let rec = ActionRecord(id: UUID(), actionID: "vitals.photoCleanup", title: "Clean up", findingID: nil, doneAt: t, watch: .freeSpace,
                               before: MetricsSnapshot(takenAt: t, freeBytes: 10e9), after: nil, verdict: .pending, outcomeText: nil, performedBy: "vitals")
        let soon = rec.evaluated(with: MetricsSnapshot(takenAt: t.addingTimeInterval(60), freeBytes: 9.5e9))
        #expect(soon.verdict == .pending)
        #expect(soon.outcomeText?.contains("Recently Deleted") == true)
        let emptied = rec.evaluated(with: MetricsSnapshot(takenAt: t.addingTimeInterval(86_400), freeBytes: 12e9))
        #expect(emptied.verdict == .improved)
    }

    @Test func safetyCasesSaySeekService() {
        #expect(AdviceCatalog.safety(for: "heat.now")?.title.contains("Stop using") == true)
    }

    @Test func noMythActions() {
        let text = AdviceCatalog.allActionIDs.compactMap(AdviceCatalog.action).map { ($0.title + $0.why + $0.steps.joined()).lowercased() }.joined()
        #expect(!text.contains("clear ram"))
        #expect(!text.contains("boost"))
        #expect(!text.contains("calibrat"))
        #expect(AdviceCatalog.myth("clearRam")?.contains("restart") == true)
    }

    @Test func glossary() {
        #expect(ProcessGlossary.shortName("com.apple.cloudd") == "cloudd")
        #expect(ProcessGlossary.entry(for: "bird")?.group == "icloudSync")
        #expect(ProcessGlossary.display("healthd") == "Health (healthd)")
        #expect(ProcessGlossary.display("SomeUnknownDaemon") == "SomeUnknownDaemon")
        #expect(ProcessGlossary.entry(for: "com.apple.HearingApp.HearingWidgetExtension")?.group == "widget")
    }

    @Test func optimiseOnlyRelevantItems() {
        let healthy = OptimiseEngine.items(checkup: nil, samples: [], events: [], days: [], health:
            BatteryHealth(maxCapacityPercent: 98, cycleCount: 40, designCapacity: nil, fullChargeCapacity: nil, asOf: t0, sourceFile: "s", keysUsed: [], percentProvenance: .screenshot),
                                           benchmark: nil, now: t0)
        #expect(!healthy.contains { $0.id == "opt.cycles" })
        #expect(!healthy.contains { $0.id == "opt.capacityUnknown" })
        #expect(healthy.contains { $0.id == "opt.shareAnalytics" })
        let full = (0..<20).map { Sample(takenAt: t0.addingTimeInterval(Double(-$0) * 1800), thermal: .nominal, batteryLevel: 1, charge: .full, lowPowerMode: false, source: .app) }
        #expect(OptimiseEngine.items(checkup: nil, samples: full, events: [], days: [], health: nil, benchmark: nil, now: t0).contains { $0.id == "opt.heldFull" })
    }

    @Test func outcomesSayNoChangePlainly() {
        let a = ActionRecord(actionID: "relief.coolDown", title: "Cool down", findingID: nil, doneAt: t0, watch: .thermalNow,
                             before: MetricsSnapshot(takenAt: t0, thermal: .serious), performedBy: "shortcut")
        #expect(a.evaluated(with: MetricsSnapshot(takenAt: t0, thermal: .serious)).verdict == .noChange)
        #expect(a.evaluated(with: MetricsSnapshot(takenAt: t0, thermal: .fair)).verdict == .improved)
        let f = ActionRecord(actionID: "vitals.photoCleanup", title: "Photos", findingID: nil, doneAt: t0, watch: .freeSpace,
                             before: MetricsSnapshot(takenAt: t0, freeBytes: 1e9), performedBy: "vitals")
        #expect(f.evaluated(with: MetricsSnapshot(takenAt: t0, freeBytes: 3.5e9)).outcomeText?.contains("Freed") == true)
    }
}

@Suite struct ScreenshotParserTests {
    @Test func appListOneOrTwoLines() {
        let r = BatteryScreenshotParser.parse(["Battery", "Last 24 Hours", "Activity", "Home & Lock Screen 18%", "Safari", "12%", "Maps 9%",
                                               "Show Activity", "Screen On 3 hr 10 min", "Photos 4%"])
        #expect(r.apps.map(\.app) == ["Home & Lock Screen", "Safari", "Maps", "Photos"])
        #expect(r.apps.first?.percent == 18)
        #expect(r.periodLabel == "Last 24 Hours")
    }

    @Test func maximumCapacity() {
        #expect(BatteryScreenshotParser.parse(["Battery Health", "Maximum Capacity", "100%"]).maximumCapacity == 100)
        #expect(BatteryScreenshotParser.parse(["Maximum Capacity 87%"]).maximumCapacity == 87)
    }
}

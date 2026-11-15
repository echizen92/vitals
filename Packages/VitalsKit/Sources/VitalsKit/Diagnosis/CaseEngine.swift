import Foundation

// A diagnosis is a case, not a single verdict (plan §4b item 1). The Duo case went: expected and temporary
// (first night of a restore) → likely stuck iCloud Drive sync (live writes far beyond the drive's size) →
// relieved by a restart, being watched. The engine re-derives hypotheses from all evidence each time; the
// stored CaseRecord keeps every earlier verdict so revisions are visible.

/// A fact no file holds, asked of the person (plan §4a item 10). Shown as "You told Vitals".
public struct UserFact: Codable, Sendable, Hashable, Identifiable {
    public enum Key: String, Codable, Sendable, CaseIterable {
        case icloudDriveGB
        public var question: String {
            switch self { case .icloudDriveGB: "How much is stored in your iCloud Drive?" }
        }
        public var help: String {
            switch self {
            case .icloudDriveGB: "Settings > [your name] > iCloud shows it. Vitals compares it with how much the sync has written."
            }
        }
        public var unit: String { switch self { case .icloudDriveGB: "GB" } }
    }
    public var key: Key
    public var value: Double
    public var enteredAt: Date
    public var id: Key { key }
    public init(key: Key, value: Double, enteredAt: Date) { self.key = key; self.value = value; self.enteredAt = enteredAt }
}

/// A write or CPU rate for one process over a window, from deltas between two timestamped snapshots
/// (Mac companion, Developer Mode). Never from a single snapshot.
public struct ProcessRate: Codable, Sendable, Hashable {
    public var process: String
    public var bytesWrittenPerMinute: Double
    public var cpuPercent: Double?
    public var from: Date
    public var to: Date
    public init(process: String, bytesWrittenPerMinute: Double, cpuPercent: Double?, from: Date, to: Date) {
        self.process = process; self.bytesWrittenPerMinute = bytesWrittenPerMinute; self.cpuPercent = cpuPercent; self.from = from; self.to = to
    }
}

/// "Written since the process started", read from one snapshot (Mac companion).
public struct ProcessTotal: Codable, Sendable, Hashable {
    public var process: String
    public var bytesWritten: Double
    public var since: Date?
    public var at: Date
    public init(process: String, bytesWritten: Double, since: Date?, at: Date) {
        self.process = process; self.bytesWritten = bytesWritten; self.since = since; self.at = at
    }
}

/// One hypothesis about what is going on.
public struct Hypothesis: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var status: Status
    public var confidence: Confidence
    public var tier: AccessTier
    public var reasoning: [Evidence]
    public var adviceKey: String
    /// A fact that would settle it, if not yet given.
    public var asks: UserFact.Key?
    /// When to look again (e.g. after the next 08:00 analytics file).
    public var recheckAfter: Date?
}

public enum CaseState: String, Codable, Sendable, CaseIterable {
    case open, actionSuggested, actionTaken, resolvedWatching, resolved, cameBack
    public var label: String {
        switch self {
        case .open: "Open"
        case .actionSuggested: "Action suggested"
        case .actionTaken: "Action taken, measuring"
        case .resolvedWatching: "Better, watching"
        case .resolved: "Resolved"
        case .cameBack: "Came back"
        }
    }
}

public struct CaseInput: Sendable {
    public var days: [AnalyticsDay]
    public var events: [LogEvent]
    public var facts: [UserFact]
    public var rates: [ProcessRate]
    public var totals: [ProcessTotal]
    public var actions: [ActionRecord]
    public var now: Date
    public init(days: [AnalyticsDay] = [], events: [LogEvent] = [], facts: [UserFact] = [], rates: [ProcessRate] = [],
                totals: [ProcessTotal] = [], actions: [ActionRecord] = [], now: Date = .now) {
        self.days = days; self.events = events; self.facts = facts; self.rates = rates; self.totals = totals; self.actions = actions; self.now = now
    }
}

public struct CaseResult: Codable, Sendable, Hashable {
    public var hypotheses: [Hypothesis]
    public var state: CaseState
    public var couldNotDetermine: [String]
    public var evaluatedAt: Date
    public var primary: Hypothesis? { hypotheses.first }
}

public enum CaseEngine {
    static let syncProcesses = ["bird", "cloudd"]
    static let gb = 1e9

    public static func evaluate(_ i: CaseInput) -> CaseResult {
        var hs: [Hypothesis] = []
        let days = i.days.sorted { $0.date < $1.date }
        let cal = Calendar.current
        let setupDay = days.first { $0.looksLikeSetupDay }
        let latest = days.last
        let otaEvents = i.events.filter { $0.kind == .osUpdate }
        let drive = i.facts.first { $0.key == .icloudDriveGB }?.value
        let nextRecheck = nextEight(after: i.now)

        // --- Context: new phone / restore / update / reindexing (expected and temporary) ---
        var context: [Evidence] = []
        if let s = setupDay {
            if let src = s.setupDataSource { context.append(Evidence(text: "Set up as a new phone from \(src) (ExpressSetup)", provenance: .parsedFromLog, source: s.sourceFile)) }
            if s.fromFactory == true { context.append(Evidence(text: "First setup of this phone (Datamigrator: from factory)", provenance: .parsedFromLog, source: s.sourceFile)) }
            if s.successfulInstalls > 0 { context.append(Evidence(text: "\(s.successfulInstalls) apps installed that day", provenance: .parsedFromLog, source: s.sourceFile)) }
        }
        if let o = otaEvents.first { context.append(Evidence(text: "iOS update finished \(o.timestamp.formatted(date: .abbreviated, time: .shortened))", provenance: .parsedFromLog, source: o.importID)) }
        if let d = latest, d.spotlightRebuilds > 0 { context.append(Evidence(text: "Search index rebuilt \(d.spotlightRebuilds)×", provenance: .parsedFromLog, source: d.sourceFile)) }
        if let d = days.last(where: { $0.healthRestoreUnfinished != nil }), d.healthRestoreUnfinished == true {
            context.append(Evidence(text: "Health restore from iCloud not finished yet", provenance: .parsedFromLog, source: d.sourceFile))
        }
        if let d = latest, d.elevatedThermalSeconds > 0 {
            let light = d.thermalPressureSeconds["Light"] ?? 0, mod = d.elevatedThermalSeconds - light
            context.append(Evidence(text: "Ran warm for \(DurationFormatting.string(seconds: d.elevatedThermalSeconds)) (Light \(DurationFormatting.string(seconds: light)), Moderate or above \(DurationFormatting.string(seconds: mod)))", provenance: .parsedFromLog, source: d.sourceFile))
        }
        if let d = latest {
            for w in d.diskWrites.prefix(4) where w.bytesWritten >= 5 * gb {
                context.append(Evidence(text: "\(ProcessGlossary.display(w.process)) wrote \(ByteFormatting.string(w.bytesWritten)) that day (time not recorded)", provenance: .parsedFromLog, source: d.sourceFile))
            }
        }
        let setupAge = setupDay.map { cal.dateComponents([.day], from: cal.startOfDay(for: $0.date), to: cal.startOfDay(for: i.now)).day ?? 0 }
        let inSetupWindow = (setupDay != nil && (setupAge ?? 99) <= 3) || (otaEvents.contains { i.now.timeIntervalSince($0.timestamp) < 3 * 86_400 })

        // --- Write amplification / stuck iCloud Drive sync (plan §4b items 3–4) ---
        var stuck: Hypothesis?
        let birdRate = i.rates.first { ProcessGlossary.shortName($0.process) == "bird" }?.bytesWrittenPerMinute
        let clouddRate = i.rates.first { ProcessGlossary.shortName($0.process) == "cloudd" }?.bytesWrittenPerMinute
        let downloaderRate = i.rates.first { ProcessGlossary.shortName($0.process) == "nsurlsessiond" }?.bytesWrittenPerMinute
        let liveTotal = syncProcesses.compactMap { p in i.totals.filter { ProcessGlossary.shortName($0.process) == p }.map(\.bytesWritten).max() }.max()
        let syncPerDay = days.map { d in (d, syncProcesses.compactMap { d.bytesWritten(process: $0) }.reduce(0, +)) }
        let cumulative = syncPerDay.map(\.1).reduce(0, +)
        let laterDays = syncPerDay.filter { pair in setupDay.map { cal.startOfDay(for: pair.0.date) > cal.startOfDay(for: $0.date) } ?? true }
        var r: [Evidence] = []
        var conf: Confidence?
        var tier: AccessTier = .phoneOnly

        if let b = birdRate, let c = clouddRate, b > 50e6, c > 50e6 {
            // Live route (tier 2): both still writing hard.
            tier = .macDeveloper
            r.append(Evidence(text: "iCloud Drive (bird) writing \(mbPerMin(b)), iCloud sync (cloudd) \(mbPerMin(c)), measured between two snapshots", provenance: .measured, source: "Mac companion"))
            let lockstep = abs(b - c) / max(b, c) < 0.25
            if lockstep { r.append(Evidence(text: "The two move in lockstep", provenance: .inferred)) }
            if let dl = downloaderRate {
                r.append(Evidence(text: "Downloads (nsurlsessiond) wrote only \(mbPerMin(dl)) in the same window", provenance: .measured, source: "Mac companion"))
            }
            let downloaderIdle = downloaderRate.map { $0 < 0.1 * min(b, c) } ?? false
            conf = downloaderIdle ? .likely : .possible
        }
        if let t = liveTotal, t > 0 {
            tier = max(tier, .mac)
            r.append(Evidence(text: "Written since the sync last started: \(ByteFormatting.string(t))", provenance: .measured, source: "Mac companion"))
        }
        // Phone-only route (tier 0): day over day from the analytics file.
        if let later = laterDays.last, later.1 >= 10 * gb {
            r.append(Evidence(text: "Still \(ByteFormatting.string(later.1)) written by bird and cloudd on \(later.0.date.formatted(date: .abbreviated, time: .omitted)), a day after setup (daily totals; slower and weaker than a live measurement)", provenance: .parsedFromLog, source: later.0.sourceFile))
            conf = max(conf ?? .possible, .possible)
        }
        if conf != nil || (cumulative >= 20 * gb && drive != nil) {
            let written = max(liveTotal ?? 0, cumulative)
            if let drive {
                let ratio = written / (drive * gb)
                r.append(Evidence(text: "You said iCloud Drive holds about \(Int(drive)) GB", provenance: .userSupplied))
                if ratio >= 2 {
                    r.append(Evidence(text: "The sync has written about \(String(format: "%.1f", ratio))× the size of the whole drive: it is rewriting its own data rather than making progress", provenance: .inferred))
                    // Live evidence with an idle downloader, or a later day still writing, makes it likely.
                    if conf == .likely || !laterDays.filter({ $0.1 >= 10 * gb }).isEmpty || conf == .possible { conf = .likely }
                } else {
                    r.append(Evidence(text: "That is within what a full download of the drive would write", provenance: .inferred))
                    conf = .possible
                }
            } else {
                conf = conf ?? .possible
            }
        }
        if let conf {
            r.append(Evidence(text: "Not proven: bytes written include database rewrites, and cloudd syncs other iCloud data too, so the logs cannot show which file is looping", provenance: .inferred))
            stuck = Hypothesis(id: "icloud.stuckSync", title: conf == .possible ? "Possibly a stuck iCloud Drive sync" : "Likely stuck iCloud Drive sync",
                               summary: conf == .likely
                                ? "iCloud Drive has been rewriting far more than it holds. A restart usually stops it."
                                : "iCloud sync is still writing a lot. Tell Vitals your iCloud Drive size to tell a big sync from a stuck one.",
                               status: .attention, confidence: conf, tier: tier, reasoning: r, adviceKey: "icloud.stuckSync",
                               asks: drive == nil ? .icloudDriveGB : nil, recheckAfter: nextRecheck)
        }

        // --- Proof by intervention (plan §4b item 2) ---
        var state: CaseState = .open
        if let restart = i.actions.filter({ $0.actionID == "relief.restart" || $0.actionID == "guided.restart" }).sorted(by: { $0.doneAt < $1.doneAt }).last {
            if let before = restart.before.syncBytesPerMinute, let after = restart.after?.syncBytesPerMinute {
                if after < 0.2 * before {
                    if var s = stuck ?? Optional(Hypothesis(id: "icloud.stuckSync", title: "Likely stuck iCloud Drive sync", summary: "", status: .attention,
                                                            confidence: .possible, tier: .macDeveloper, reasoning: [], adviceKey: "icloud.stuckSync", asks: nil, recheckAfter: nil)) {
                        s.reasoning.append(Evidence(text: "After the restart, iCloud sync writes fell from \(mbPerMin(before)) to \(mbPerMin(after)), with no large download following. That supports a stuck sync over a legitimate one.", provenance: .measured, source: "before/after capture"))
                        s.summary = "The restart stopped the sync churn. Vitals keeps watching in case it comes back."
                        s.status = .expected
                        s.confidence = max(s.confidence, .likely)
                        s.title = "Likely stuck iCloud Drive sync, eased by a restart"
                        stuck = s
                    }
                    state = .resolvedWatching
                    // Came back: a later day (after the action) still writing heavily.
                    if let d = syncPerDay.last, d.0.date > restart.doneAt.addingTimeInterval(12 * 3600) {
                        if d.1 >= 10 * gb { state = .cameBack; stuck?.status = .attention; stuck?.summary = "The sync churn came back after the restart. Time for the next step." }
                        else if d.1 < 2 * gb { state = .resolved }
                    }
                } else {
                    stuck?.reasoning.append(Evidence(text: "The restart did not lower iCloud sync writes (\(mbPerMin(before)) → \(mbPerMin(after))).", provenance: .measured, source: "before/after capture"))
                    state = .actionTaken
                }
            } else {
                state = .actionTaken
            }
        } else if stuck != nil {
            state = .actionSuggested
        }
        if let s = stuck { hs.append(s) }

        // --- Expected and temporary (plan §4a item 1) ---
        if inSetupWindow && !context.isEmpty {
            let until = setupDay.map { cal.date(byAdding: .day, value: 3, to: $0.date)! }
            hs.append(Hypothesis(
                id: "context.newPhone", title: "Expected, temporary: a new phone settling in",
                summary: "This phone was set up recently. Restoring apps, iCloud data, Health and search indexes heats and drains a phone for one to three days. This is normal.\(stuck == nil ? " A restart is harmless and sometimes helps; the load may simply be normal." : "")",
                status: .expected, confidence: setupDay != nil ? .confirmed : .likely, tier: .phoneOnly, reasoning: context,
                adviceKey: "context.newPhone", asks: nil, recheckAfter: until.map { max($0, nextRecheck) } ?? nextRecheck))
        }

        // --- Unexpected restarts (plan §4a item 4) ---
        let resets = days.map(\.watchdogResets).reduce(0, +)
        if resets > 0 {
            let updateReboot = !otaEvents.isEmpty
            let unexplained = max(0, resets - (updateReboot ? 1 : 0))
            var ev = days.flatMap { d in d.shutdownReasons.filter { $0.contains("wdog") }.map { Evidence(text: "Shutdown reason: \($0)", provenance: .parsedFromLog, source: d.sourceFile) } }
            if updateReboot { ev.append(Evidence(text: "One restart may be the iOS update's own reboot", provenance: .inferred)) }
            ev.append(Evidence(text: "No panic report on the phone, so the logs do not say what hung", provenance: .inferred))
            if unexplained > 0 {
                hs.append(Hypothesis(id: "restart.unexpected", title: unexplained == 1 ? "One unexplained restart" : "\(unexplained) unexplained restarts",
                                     summary: "The phone restarted on its own (a watchdog reset). Once is not a fault, especially under restore load. If it happens again, note the time.",
                                     status: inSetupWindow ? .expected : .attention, confidence: .confirmed, tier: .phoneOnly, reasoning: ev,
                                     adviceKey: "restart.unexpected", asks: nil, recheckAfter: nil))
            }
            if days.contains(where: { $0.thermalResets > 0 }) {
                hs.append(Hypothesis(id: "restart.thermal", title: "The phone shut down because it was too hot", summary: "iOS recorded a thermal reset.",
                                     status: .problem, confidence: .confirmed, tier: .phoneOnly,
                                     reasoning: [Evidence(text: "ResetTelemetry2 thermal flag set", provenance: .parsedFromLog)], adviceKey: "heat.thermalShutdown", asks: nil, recheckAfter: nil))
            }
        }

        // --- Heat with nothing to explain it ---
        if !inSetupWindow, stuck == nil, let d = latest, d.elevatedThermalSeconds >= 3600 {
            var ev = [Evidence(text: "\(DurationFormatting.string(seconds: d.elevatedThermalSeconds)) at Light thermal pressure or above", provenance: .parsedFromLog, source: d.sourceFile)]
            ev += d.powerExceptions.prefix(3).map { Evidence(text: "\(ProcessGlossary.display($0.process)) flagged for power \($0.count)×", provenance: .parsedFromLog, source: d.sourceFile) }
            ev += d.diskWrites.prefix(3).map { Evidence(text: "\(ProcessGlossary.display($0.process)) wrote \(ByteFormatting.string($0.bytesWritten))", provenance: .parsedFromLog, source: d.sourceFile) }
            hs.append(Hypothesis(id: "heat.unexplained", title: "Hours of heat with no setup or update to explain them",
                                 summary: "Look at the busiest processes below. The daily file gives the day, not the hour.", status: .attention, confidence: .likely,
                                 tier: .phoneOnly, reasoning: ev, adviceKey: "heat.unexplained", asks: nil, recheckAfter: nextRecheck))
        }

        // Order: anything needing action first, then expected context, then the rest.
        hs.sort { a, b in
            if a.status != b.status { return a.status > b.status }
            return a.confidence > b.confidence
        }

        var cnd: [String] = []
        if days.isEmpty { cnd.append("Which processes were busy, restarts and thermal pressure: share the newest daily analytics file (written about 08:00).") }
        if !days.isEmpty && i.rates.isEmpty { cnd.append("Exact times within the day: the daily analytics file records totals only. Individual reports or a Mac capture give the minute.") }
        cnd.append("Which app used which share of the battery: only Settings > Battery shows it. Share a screenshot of that screen.")
        cnd.append("Battery temperature in degrees: iOS gives apps only the pressure level (normal, warm, hot).")
        if stuck != nil { cnd.append("Which iCloud file or container is looping: no log names it.") }
        if let first = days.first, first.looksLikeSetupDay { cnd.append("Anything before \(first.date.formatted(date: .abbreviated, time: .omitted)): there are no logs from before setup.") }
        if resets > 0 { cnd.append("What caused the watchdog reset: there is no panic report.") }

        return CaseResult(hypotheses: hs, state: hs.isEmpty ? .resolved : state, couldNotDetermine: cnd, evaluatedAt: i.now)
    }

    static func mbPerMin(_ bytes: Double) -> String { "\(Int((bytes / 1e6).rounded())) MB/min" }

    /// The next 09:00 local time, by which the day's 08:00 analytics file exists.
    public static func nextEight(after d: Date) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: d)
        c.hour = 9
        let today = cal.date(from: c)!
        return today > d ? today : cal.date(byAdding: .day, value: 1, to: today)!
    }
}

/// The stored case: the latest result plus every earlier primary verdict, so revisions are visible.
public struct CaseRecord: Codable, Sendable, Hashable {
    public struct Revision: Codable, Sendable, Hashable {
        public var at: Date
        public var title: String
        public var status: Status
        public var confidence: Confidence
        public var state: CaseState
    }
    public var current: CaseResult
    public var history: [Revision]

    public init(current: CaseResult, history: [Revision] = []) { self.current = current; self.history = history }

    /// Applies a new evaluation. If the primary verdict or state changed, the earlier one goes into history.
    public func revised(with new: CaseResult) -> CaseRecord {
        var h = history
        if let old = current.primary,
           old.id != new.primary?.id || old.status != new.primary?.status || old.confidence != new.primary?.confidence || current.state != new.state {
            h.append(Revision(at: current.evaluatedAt, title: old.title, status: old.status, confidence: old.confidence, state: current.state))
        }
        return CaseRecord(current: new, history: h)
    }
}

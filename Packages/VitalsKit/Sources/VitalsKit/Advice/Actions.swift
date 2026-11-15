import Foundation

/// What Vitals could measure at a moment, for before/after comparisons around an action.
public struct MetricsSnapshot: Codable, Sendable, Hashable {
    public var takenAt: Date
    public var freeBytes: Double?
    public var thermal: ThermalLevel?
    public var drainPerHour: Double?
    /// bird + cloudd writes per minute (Mac companion only).
    public var syncBytesPerMinute: Double?
    /// Seconds at Light thermal pressure or above, from the latest daily analytics file.
    public var elevatedThermalSecondsDay: Double?
    public var dayOf: Date?

    public init(takenAt: Date, freeBytes: Double? = nil, thermal: ThermalLevel? = nil, drainPerHour: Double? = nil,
                syncBytesPerMinute: Double? = nil, elevatedThermalSecondsDay: Double? = nil, dayOf: Date? = nil) {
        self.takenAt = takenAt; self.freeBytes = freeBytes; self.thermal = thermal; self.drainPerHour = drainPerHour
        self.syncBytesPerMinute = syncBytesPerMinute; self.elevatedThermalSecondsDay = elevatedThermalSecondsDay; self.dayOf = dayOf
    }
}

/// Which reading an action is judged by.
public enum WatchMetric: String, Codable, Sendable, CaseIterable {
    case freeSpace, thermalNow, drain, syncWrites, thermalPressureDay, none
}

/// The person did something Vitals suggested (or Vitals did it). Stored locally and included in the report.
public struct ActionRecord: Codable, Sendable, Hashable, Identifiable {
    public enum Verdict: String, Codable, Sendable { case pending, improved, noChange, worse, unmeasurable
        public var label: String {
            switch self {
            case .pending: "Measuring"
            case .improved: "Helped"
            case .noChange: "No change"
            case .worse: "Worse"
            case .unmeasurable: "Could not measure"
            }
        }
    }
    public var id: UUID
    public var actionID: String
    public var title: String
    public var findingID: String?
    public var doneAt: Date
    public var watch: WatchMetric
    public var before: MetricsSnapshot
    public var after: MetricsSnapshot?
    public var verdict: Verdict
    public var outcomeText: String?
    /// "vitals" (Vitals did it), "shortcut", "guided" or "manual".
    public var performedBy: String

    public init(id: UUID = UUID(), actionID: String, title: String, findingID: String?, doneAt: Date, watch: WatchMetric,
                before: MetricsSnapshot, after: MetricsSnapshot? = nil, verdict: Verdict = .pending, outcomeText: String? = nil, performedBy: String) {
        self.id = id; self.actionID = actionID; self.title = title; self.findingID = findingID; self.doneAt = doneAt; self.watch = watch
        self.before = before; self.after = after; self.verdict = verdict; self.outcomeText = outcomeText; self.performedBy = performedBy
    }

    /// When the follow-up comparison can be made.
    public var dueAt: Date {
        switch watch {
        case .freeSpace: doneAt.addingTimeInterval(5)
        case .thermalNow: doneAt.addingTimeInterval(10 * 60)
        case .drain: doneAt.addingTimeInterval(6 * 3600)
        case .syncWrites: doneAt.addingTimeInterval(5 * 60)
        case .thermalPressureDay: CaseEngine.nextEight(after: doneAt)
        case .none: doneAt
        }
    }

    /// Compares before and after for the watched metric and says it plainly, including "no change".
    public func evaluated(with after: MetricsSnapshot) -> ActionRecord {
        var r = self
        r.after = after
        func pct(_ a: Double, _ b: Double) -> Double { a == 0 ? 0 : (b - a) / abs(a) }
        switch watch {
        case .freeSpace:
            if let a = before.freeBytes, let b = after.freeBytes {
                let d = b - a
                // Deleted photos sit in Recently Deleted for up to 30 days, so space does not come back at once.
                // Judging that as "worse" or "no change" would be wrong: keep measuring until it is emptied.
                if actionID == "vitals.photoCleanup", d <= 50e6 {
                    if after.takenAt < doneAt.addingTimeInterval(31 * 86_400) {
                        r.verdict = .pending
                        r.outcomeText = "In Recently Deleted. The space comes back when it is emptied (Photos > Albums > Recently Deleted, or by itself after 30 days); Vitals checks again then."
                    } else {
                        r.verdict = .noChange
                        r.outcomeText = "No measurable change in free space 30 days later (other apps may have used the space)."
                    }
                    return r
                }
                if d > 50e6 { r.verdict = .improved; r.outcomeText = "Freed \(ByteFormatting.string(d))." }
                else if d < -50e6 { r.verdict = .worse; r.outcomeText = "Free space went down by \(ByteFormatting.string(-d)) (other apps may have written meanwhile)." }
                else { r.verdict = .noChange; r.outcomeText = "No measurable change in free space." }
            } else { r.verdict = .unmeasurable }
        case .thermalNow:
            if let a = before.thermal, let b = after.thermal {
                if b < a { r.verdict = .improved; r.outcomeText = "Cooled from \(a.label.lowercased()) to \(b.label.lowercased()) in 10 minutes." }
                else if b > a { r.verdict = .worse; r.outcomeText = "Got warmer: \(a.label.lowercased()) to \(b.label.lowercased())." }
                else { r.verdict = .noChange; r.outcomeText = "Still \(b.label.lowercased()) after 10 minutes." }
            } else { r.verdict = .unmeasurable }
        case .drain:
            if let a = before.drainPerHour, let b = after.drainPerHour {
                let c = pct(a, b)
                if c <= -0.2 { r.verdict = .improved; r.outcomeText = "Drain fell from \(Int(a.rounded()))% to \(Int(b.rounded()))% an hour." }
                else if c >= 0.2 { r.verdict = .worse; r.outcomeText = "Drain rose from \(Int(a.rounded()))% to \(Int(b.rounded()))% an hour." }
                else { r.verdict = .noChange; r.outcomeText = "Drain about the same (\(Int(b.rounded()))% an hour). Try the next step." }
            } else { r.verdict = .unmeasurable; r.outcomeText = "Not enough samples on battery to compare drain yet." }
        case .syncWrites:
            if let a = before.syncBytesPerMinute, let b = after.syncBytesPerMinute {
                if b < 0.2 * a { r.verdict = .improved; r.outcomeText = "iCloud sync writes fell from \(Int(a / 1e6)) to \(Int(b / 1e6)) MB a minute." }
                else { r.verdict = .noChange; r.outcomeText = "iCloud sync still writing \(Int(b / 1e6)) MB a minute." }
            } else { r.verdict = .unmeasurable; r.outcomeText = "Needs a Mac capture before and after to measure." }
        case .thermalPressureDay:
            if let a = before.elevatedThermalSecondsDay, let b = after.elevatedThermalSecondsDay, after.dayOf != before.dayOf {
                let c = pct(a, b)
                if c <= -0.3 { r.verdict = .improved; r.outcomeText = "Time running warm fell from \(DurationFormatting.string(seconds: a)) to \(DurationFormatting.string(seconds: b)) a day." }
                else if c >= 0.3 { r.verdict = .worse; r.outcomeText = "Time running warm rose from \(DurationFormatting.string(seconds: a)) to \(DurationFormatting.string(seconds: b))." }
                else { r.verdict = .noChange; r.outcomeText = "About the same time running warm (\(DurationFormatting.string(seconds: b)))." }
            } else { r.verdict = .pending; r.outcomeText = "Waiting for tomorrow's analytics file." }
        case .none:
            r.verdict = .unmeasurable
        }
        return r
    }
}

import Foundation

/// A process named as a possible cause of a hot spell, with the evidence behind it.
public struct Culprit: Sendable, Hashable, Identifiable {
    public var process: String
    /// Relative weight of evidence, 0...1 across the list (the top culprit is 1).
    public var score: Double
    public var rawScore: Double
    public var events: [LogEvent]
    /// When the strongest event happened, to place the culprit on the timeline ("the reveal").
    public var peakAt: Date
    public var id: String { process }

    public var summary: String {
        let kinds = Dictionary(grouping: events, by: \.kind).sorted { $0.key.heatWeight > $1.key.heatWeight }
        return kinds.map { "\($0.value.count == 1 ? "" : "\($0.value.count)× ")\($0.key.label.prefix(1).lowercased() + $0.key.label.dropFirst())" }.joined(separator: ", ")
    }
}

/// Matches log events to a hot spell's time window and ranks the processes by evidence.
/// This is inference: a report near a spell is a lead, not proof, and the UI says so.
public enum Correlator {
    /// Events up to `margin` before or after the spell count, weighted down with distance.
    public static func culprits(for spell: HotSpell, events: [LogEvent], margin: TimeInterval = 30 * 60) -> [Culprit] {
        let lo = spell.start.addingTimeInterval(-margin), hi = spell.end.addingTimeInterval(margin)
        let near = events.filter { $0.timestamp >= lo && $0.timestamp <= hi && $0.kind != .panic }
        var byProcess: [String: (Double, [LogEvent], Date, Double)] = [:]
        for e in near {
            let distance: TimeInterval = e.timestamp < spell.start ? spell.start.timeIntervalSince(e.timestamp)
                : e.timestamp > spell.end ? e.timestamp.timeIntervalSince(spell.end) : 0
            let proximity = 1 - 0.7 * (distance / margin)
            // CPU reports carry how much CPU was used; more CPU, more weight (capped).
            var magnitude = 1.0
            if e.kind == .cpuResource, let m = e.magnitude { magnitude = min(3, max(0.5, m / 60)) }
            if e.kind == .liveCPU, let m = e.magnitude { magnitude = min(3, max(0.3, m / 50)) }
            let s = e.kind.heatWeight * proximity * magnitude
            var entry = byProcess[e.process] ?? (0, [], e.timestamp, 0)
            entry.0 += s
            entry.1.append(e)
            if s > entry.3 { entry.2 = e.timestamp; entry.3 = s }
            byProcess[e.process] = entry
        }
        let top = byProcess.values.map(\.0).max() ?? 1
        return byProcess.map { name, v in
            Culprit(process: name, score: v.0 / top, rawScore: v.0, events: v.1.sorted { $0.timestamp < $1.timestamp }, peakAt: v.2)
        }
        .sorted { $0.rawScore != $1.rawScore ? $0.rawScore > $1.rawScore : $0.process < $1.process }
    }
}

/// Crashes and hangs by app, for the Logs screen.
public struct CrashSummary: Sendable, Hashable, Identifiable {
    public var process: String
    public var crashes: Int
    public var hangs: Int
    public var last: Date
    public var events: [LogEvent]
    public var id: String { process }

    public static func build(from events: [LogEvent]) -> [CrashSummary] {
        let relevant = events.filter { $0.kind == .crash || $0.kind == .hang }
        return Dictionary(grouping: relevant, by: \.process).map { p, es in
            CrashSummary(process: p, crashes: es.filter { $0.kind == .crash }.count, hangs: es.filter { $0.kind == .hang }.count,
                         last: es.map(\.timestamp).max() ?? .distantPast, events: es.sorted { $0.timestamp > $1.timestamp })
        }
        .sorted { ($0.crashes + $0.hangs, $0.last) > ($1.crashes + $1.hangs, $1.last) }
    }
}

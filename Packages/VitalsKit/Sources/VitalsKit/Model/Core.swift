import Foundation

/// Where a value came from. Every reading in Vitals carries one, and the UI always shows it.
public enum Provenance: String, Codable, Sendable, CaseIterable {
    /// Read directly from a public API on this phone.
    case measured
    /// Taken from a system file the person shared in (analytics, .ips, sysdiagnose, companion bundle).
    case parsedFromLog
    /// Worked out by Vitals from other readings (drain rate, hot spells, verdicts).
    case inferred
    /// A fact the person told Vitals (for example how big their iCloud Drive is).
    case userSupplied
    /// Read with on-device text recognition from a screenshot the person shared, then confirmed by them.
    case screenshot
    /// Handed back by a Vitals shortcut run in the Shortcuts app.
    case shortcuts

    public var label: String {
        switch self {
        case .measured: "Measured"
        case .parsedFromLog: "From a log"
        case .inferred: "Inferred"
        case .userSupplied: "You told Vitals"
        case .screenshot: "Read from screenshot"
        case .shortcuts: "Read via Shortcuts"
        }
    }

    public var explanation: String {
        switch self {
        case .measured: "Read directly from iOS on this phone."
        case .parsedFromLog: "Read from a system file you shared into Vitals."
        case .inferred: "Worked out by Vitals from other readings."
        case .userSupplied: "A fact you entered. Vitals cannot check it."
        case .screenshot: "Read from your screenshot on this phone and confirmed by you."
        case .shortcuts: "Read by a Vitals shortcut and handed back to the app."
        }
    }
}

/// The six areas of the check-up scorecard.
public enum Area: String, Codable, Sendable, CaseIterable, Identifiable {
    case battery, heat, storage, memory, network, software

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .battery: "Battery"
        case .heat: "Heat"
        case .storage: "Storage"
        case .memory: "Memory & performance"
        case .network: "Network"
        case .software: "Software"
        }
    }

    public var shortTitle: String {
        switch self {
        case .memory: "Memory"
        default: title
        }
    }

    public var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .heat: "thermometer.medium"
        case .storage: "internaldrive"
        case .memory: "memorychip"
        case .network: "antenna.radiowaves.left.and.right"
        case .software: "gearshape.2"
        }
    }
}

/// The verdict for one area. `unknown` is legitimate: it means Vitals needs a log import or a reading it cannot take.
/// `expected` means something is happening that looks like a fault but is normal and temporary
/// (a new phone restoring from iCloud, an OS update, reindexing), with a date to check again.
public enum Status: String, Codable, Sendable, CaseIterable, Comparable {
    case good, expected, attention, problem, unknown

    public var label: String {
        switch self {
        case .good: "Good"
        case .expected: "Expected, temporary"
        case .attention: "Attention"
        case .problem: "Problem"
        case .unknown: "Unknown"
        }
    }

    /// Order for "worst first" sorting: problem, attention, expected, unknown, good.
    var rank: Int {
        switch self {
        case .problem: 4
        case .attention: 3
        case .expected: 2
        case .unknown: 1
        case .good: 0
        }
    }

    public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rank < rhs.rank }
}

/// A reading's value. Encoded as a plain JSON scalar so the report stays easy to read by hand.
public enum ReadingValue: Codable, Sendable, Hashable {
    case number(Double)
    case text(String)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        self = .text(try c.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .text(let s): try c.encode(s)
        case .bool(let b): try c.encode(b)
        }
    }

    public var number: Double? { if case .number(let d) = self { d } else { nil } }
    public var text: String? { if case .text(let s) = self { s } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}

/// One value with its unit, provenance, source and time. The atom of the check-up and the report.
public struct Reading: Codable, Sendable, Hashable, Identifiable {
    /// Stable dotted id, e.g. `battery.level`, `storage.free`.
    public var id: String
    public var area: Area
    /// Human label, e.g. "Battery level".
    public var label: String
    public var value: ReadingValue
    public var unit: String?
    public var provenance: Provenance
    /// The API or file the value came from, e.g. `UIDevice.batteryLevel` or `Analytics-2026-11-14.ips.ca.synced`.
    public var source: String
    public var takenAt: Date
    /// True for anything section 4 of the plan marks as unverified on real hardware.
    public var unverified: Bool

    public init(id: String, area: Area, label: String, value: ReadingValue, unit: String? = nil,
                provenance: Provenance, source: String, takenAt: Date, unverified: Bool = false) {
        self.id = id; self.area = area; self.label = label; self.value = value; self.unit = unit
        self.provenance = provenance; self.source = source; self.takenAt = takenAt; self.unverified = unverified
    }

    enum CodingKeys: String, CodingKey { case id, area, label, value, unit, provenance, source, takenAt, unverified }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        area = try c.decode(Area.self, forKey: .area)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? id
        value = try c.decode(ReadingValue.self, forKey: .value)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        provenance = try c.decode(Provenance.self, forKey: .provenance)
        source = try c.decode(String.self, forKey: .source)
        takenAt = try c.decode(Date.self, forKey: .takenAt)
        unverified = try c.decodeIfPresent(Bool.self, forKey: .unverified) ?? false
    }

    /// The value formatted with its unit for display.
    public var displayValue: String {
        switch value {
        case .bool(let b): return b ? "Yes" : "No"
        case .text(let s): return s
        case .number(let d):
            let u = unit ?? ""
            switch u {
            case "bytes": return area == .memory ? ByteFormatting.memory(d) : ByteFormatting.string(d)
            case "%": return "\(Int((d).rounded()))%"
            case "s": return DurationFormatting.string(seconds: d)
            case "": return d.formatted(.number.precision(.fractionLength(0...2)))
            default: return "\(d.formatted(.number.precision(.fractionLength(0...1)))) \(u)"
            }
        }
    }
}

public enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case info, attention, problem
    var rank: Int { switch self { case .info: 0; case .attention: 1; case .problem: 2 } }
    public static func < (l: Severity, r: Severity) -> Bool { l.rank < r.rank }
}

/// Who could see this: phone only, a Mac without Developer Mode, or a Mac with Developer Mode (plan §4c).
public enum AccessTier: Int, Codable, Sendable, CaseIterable, Comparable {
    case phoneOnly = 0, mac = 1, macDeveloper = 2
    public static func < (l: AccessTier, r: AccessTier) -> Bool { l.rawValue < r.rawValue }
    public var label: String {
        switch self {
        case .phoneOnly: "Phone only"
        case .mac: "With a Mac"
        case .macDeveloper: "Mac + Developer Mode"
        }
    }
    /// What the next tier would add, said honestly.
    public var nextTierAdds: String? {
        switch self {
        case .phoneOnly: "A Mac running Vitals Companion would read exact times and the battery registry the same day."
        case .mac: "With Developer Mode on (for technicians), the Mac could measure each process live and confirm this in minutes."
        case .macDeveloper: nil
        }
    }
}

/// How sure a finding is. Never stronger than its evidence.
public enum Confidence: String, Codable, Sendable, CaseIterable, Comparable {
    case possible, likely, confirmed
    var rank: Int { switch self { case .possible: 0; case .likely: 1; case .confirmed: 2 } }
    public static func < (l: Confidence, r: Confidence) -> Bool { l.rank < r.rank }
    public var label: String {
        switch self {
        case .possible: "Possible"
        case .likely: "Likely (inferred, not proven)"
        case .confirmed: "Confirmed"
        }
    }
}

/// How precise an event's time is. The daily analytics file has no timestamps on its samples, so its
/// events are known only to the day; individual reports give the minute (plan §4a).
public enum TimePrecision: String, Codable, Sendable { case minute, day }

/// A piece of evidence behind a finding: a reading id, a log excerpt or a plain note, each with provenance.
public struct Evidence: Codable, Sendable, Hashable {
    public var text: String
    public var provenance: Provenance
    public var readingID: String?
    public var source: String?

    public init(text: String, provenance: Provenance, readingID: String? = nil, source: String? = nil) {
        self.text = text; self.provenance = provenance; self.readingID = readingID; self.source = source
    }
}

/// Something worth telling the person, produced by the diagnosis rules.
public struct Finding: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var area: Area
    public var severity: Severity
    public var summary: String
    public var detail: String?
    public var evidence: [Evidence]
    /// Key into the advice catalogue (actions and escalation). Defaults to the id's prefix rules.
    public var adviceKey: String?
    /// The access tier whose data produced this finding.
    public var tier: AccessTier?
    public var confidence: Confidence?
    /// True for "expected and temporary" findings.
    public var expected: Bool?

    public init(id: String, area: Area, severity: Severity, summary: String, detail: String? = nil, evidence: [Evidence],
                adviceKey: String? = nil, tier: AccessTier? = nil, confidence: Confidence? = nil, expected: Bool? = nil) {
        self.id = id; self.area = area; self.severity = severity; self.summary = summary; self.detail = detail; self.evidence = evidence
        self.adviceKey = adviceKey; self.tier = tier; self.confidence = confidence; self.expected = expected
    }

    /// The catalogue key: explicit, or the id without any per-item suffix ("software.crash.Photos" → "software.crash").
    public var resolvedAdviceKey: String {
        if let adviceKey { return adviceKey }
        let parts = id.split(separator: ".")
        return parts.count > 2 ? parts.prefix(2).joined(separator: ".") : id
    }
}

/// The verdict for one area of the scorecard.
public struct AreaResult: Codable, Sendable, Hashable, Identifiable {
    public var area: Area
    public var status: Status
    /// One plain sentence.
    public var sentence: String
    public var readings: [Reading]
    public var findings: [Finding]
    /// What Vitals could not read for this area and what would settle it (plan §4a item 9).
    public var couldNotDetermine: [String]?
    public var id: Area { area }

    public init(area: Area, status: Status, sentence: String, readings: [Reading], findings: [Finding], couldNotDetermine: [String]? = nil) {
        self.area = area; self.status = status; self.sentence = sentence; self.readings = readings; self.findings = findings
        self.couldNotDetermine = couldNotDetermine
    }
}

/// One full run of the on-device check-up.
public struct Checkup: Codable, Sendable, Hashable {
    public var takenAt: Date
    public var results: [AreaResult]

    public init(takenAt: Date, results: [AreaResult]) {
        self.takenAt = takenAt; self.results = results
    }

    public func result(for area: Area) -> AreaResult? { results.first { $0.area == area } }
    public var readings: [Reading] { results.flatMap(\.readings) }
    public var findings: [Finding] { results.flatMap(\.findings) }
    public var worst: Status { results.map(\.status).max() ?? .unknown }
}

public enum ByteFormatting {
    public static func string(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    /// RAM is sold in binary units (12 GB = 12 × 2³⁰), so it is shown that way.
    public static func memory(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

public enum DurationFormatting {
    public static func string(seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 86_400 ? [.day, .hour] : seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute] : [.second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f.string(from: seconds) ?? "\(Int(seconds)) s"
    }
}

public enum DayTimeFormatting {
    /// "Today 7:01 AM", "Yesterday 11:20 PM", "Thu 3:15 PM", or a date beyond a week.
    public static func string(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday \(time)" }
        if now.timeIntervalSince(date) < 6 * 86_400 { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

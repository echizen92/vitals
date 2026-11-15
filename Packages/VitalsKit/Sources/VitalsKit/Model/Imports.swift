import Foundation

/// What kind of shared file this is.
public enum ImportKind: String, Codable, Sendable, CaseIterable {
    case analytics          // Analytics-YYYY-MM-DD-*.ips.ca.synced
    case crash              // app crash .ips
    case hang               // app hang / spin .ips
    case cpuResource        // *.cpu_resource*.ips: a process exceeded its CPU budget
    case diskWrites         // *.diskwrites_resource*.ips
    case wakeups            // *.wakeups_resource*.ips
    case jetsam             // JetsamEvent-*.ips: memory pressure
    case panic              // panic-full-*.ips: unexpected restart
    case otherIPS           // an .ips we can read the header of but do not interpret
    case sysdiagnose        // sysdiagnose_*.tar.gz
    case companionCapture   // *.vitalscapture from the Mac companion
    case unknown

    public var label: String {
        switch self {
        case .analytics: "Daily analytics"
        case .crash: "Crash report"
        case .hang: "Hang report"
        case .cpuResource: "CPU use report"
        case .diskWrites: "Disk writes report"
        case .wakeups: "Wake-ups report"
        case .jetsam: "Memory pressure report"
        case .panic: "Unexpected restart"
        case .otherIPS: "System report"
        case .sysdiagnose: "Sysdiagnose"
        case .companionCapture: "Mac companion capture"
        case .unknown: "Unrecognised file"
        }
    }
}

/// One dated event pulled from a shared file. The unit the correlator works with.
public struct LogEvent: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case crash, hang, cpuResource, diskWrites, wakeups, jetsam, jetsamLargest, panic, thermal, liveCPU, powerException, unexpectedRestart, osUpdate, other

        public var label: String {
            switch self {
            case .crash: "Crashed"
            case .hang: "Hung"
            case .cpuResource: "Used too much CPU"
            case .diskWrites: "Wrote too much to storage"
            case .wakeups: "Woke the CPU too often"
            case .jetsam: "Was stopped to free memory"
            case .jetsamLargest: "Was the largest memory user"
            case .panic: "System restarted unexpectedly"
            case .thermal: "Thermal event"
            case .liveCPU: "Was busy during a Mac capture"
            case .powerException: "Was flagged by iOS for power use"
            case .unexpectedRestart: "Phone restarted without being asked"
            case .osUpdate: "iOS was updated"
            case .other: "Event"
            }
        }

        /// How strongly this kind of event points at a process as a heat cause. Used to rank culprits.
        public var heatWeight: Double {
            switch self {
            case .cpuResource: 1.0
            case .wakeups: 0.6
            case .diskWrites: 0.4
            case .jetsamLargest: 0.35
            case .hang: 0.3
            case .crash: 0.15
            case .jetsam: 0.1
            case .thermal: 0.5
            case .liveCPU: 0.8
            case .powerException: 0.7
            case .panic, .unexpectedRestart, .osUpdate, .other: 0.05
            }
        }
    }

    public var id: String
    public var kind: Kind
    /// Process or app name, e.g. "Photos" or "mediaanalysisd".
    public var process: String
    public var bundleID: String?
    public var timestamp: Date
    /// For cpu_resource: CPU seconds used over the window. For jetsam: resident pages. Otherwise nil.
    public var magnitude: Double?
    public var magnitudeUnit: String?
    /// A short human line: "used 90 s of CPU in 180 s", "EXC_BAD_ACCESS".
    public var detail: String?
    /// The import that produced this event.
    public var importID: String
    /// nil or `.minute`: exact time from a report. `.day`: from the daily analytics file, known only to the day.
    public var precision: TimePrecision?

    public init(id: String, kind: Kind, process: String, bundleID: String? = nil, timestamp: Date, magnitude: Double? = nil,
                magnitudeUnit: String? = nil, detail: String? = nil, importID: String, precision: TimePrecision? = nil) {
        self.id = id; self.kind = kind; self.process = process; self.bundleID = bundleID; self.timestamp = timestamp
        self.magnitude = magnitude; self.magnitudeUnit = magnitudeUnit; self.detail = detail; self.importID = importID
        self.precision = precision
    }

    public var isDayPrecision: Bool { precision == .day }
}

/// Battery wear read from an analytics file. All fields optional: key names are unverified (plan §4).
public struct BatteryHealth: Codable, Sendable, Hashable {
    public var maxCapacityPercent: Double?
    public var cycleCount: Int?
    /// Design and full-charge capacities in mAh when present; used to work out a percentage if the percent key is missing.
    public var designCapacity: Double?
    public var fullChargeCapacity: Double?
    /// The date the file covers.
    public var asOf: Date
    public var sourceFile: String
    /// The exact key paths the values came from, kept for the report and for checking against real files.
    public var keysUsed: [String]
    /// Where the percentage came from when not a log: a Settings screenshot or the person typing it.
    public var percentProvenance: Provenance?

    public init(maxCapacityPercent: Double?, cycleCount: Int?, designCapacity: Double?, fullChargeCapacity: Double?,
                asOf: Date, sourceFile: String, keysUsed: [String], percentProvenance: Provenance? = nil) {
        self.maxCapacityPercent = maxCapacityPercent; self.cycleCount = cycleCount; self.designCapacity = designCapacity
        self.fullChargeCapacity = fullChargeCapacity; self.asOf = asOf; self.sourceFile = sourceFile; self.keysUsed = keysUsed
        self.percentProvenance = percentProvenance
    }

    /// The percentage, taken directly or worked out from capacities (Mac companion battery registry).
    public var effectiveMaxCapacity: (value: Double, provenance: Provenance)? {
        if let p = maxCapacityPercent { return (p, percentProvenance ?? .parsedFromLog) }
        if let d = designCapacity, let f = fullChargeCapacity, d > 0 { return (f / d * 100, .inferred) }
        return nil
    }
}

/// A file the person shared in, with what Vitals made of it.
public struct ImportRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var fileName: String
    public var kind: ImportKind
    public var importedAt: Date
    /// The time the file itself covers (header timestamp), when known.
    public var coversDate: Date?
    public var byteSize: Int64
    /// Path relative to the imports folder; nil if the original was not kept.
    public var storedPath: String?
    public var eventCount: Int
    public var notes: [String]

    public init(id: String, fileName: String, kind: ImportKind, importedAt: Date, coversDate: Date?, byteSize: Int64,
                storedPath: String?, eventCount: Int, notes: [String]) {
        self.id = id; self.fileName = fileName; self.kind = kind; self.importedAt = importedAt; self.coversDate = coversDate
        self.byteSize = byteSize; self.storedPath = storedPath; self.eventCount = eventCount; self.notes = notes
    }
}

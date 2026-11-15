import Foundation

/// Report schema v1: the machine-readable twin of the PDF, and the format of a Mac companion capture.
/// Field names follow plan §7. Additive changes keep version 1; anything that renames or removes a field
/// bumps `schemaVersion`. See Docs/report-schema.md.
public struct VitalsReport: Codable, Sendable, Hashable {
    public static let currentVersion = 1

    public struct Device: Codable, Sendable, Hashable {
        public var model: String
        public var modelIdentifier: String
        public var osVersion: String
        public var osBuild: String?
        /// Redacted by default.
        public var name: String?
        /// Serial-like identifiers (companion only: UDID, serial). Redacted by default.
        public var identifiers: [String: String]?
        public init(model: String, modelIdentifier: String, osVersion: String, osBuild: String? = nil, name: String? = nil, identifiers: [String: String]? = nil) {
            self.model = model; self.modelIdentifier = modelIdentifier; self.osVersion = osVersion; self.osBuild = osBuild
            self.name = name; self.identifiers = identifiers
        }
    }

    /// Per-process sample from the Mac companion (never produced on-device).
    public struct ProcessSample: Codable, Sendable, Hashable {
        public var takenAt: Date
        public var process: String
        public var pid: Int?
        public var cpuPercent: Double?
        /// Energy impact or similar score as reported by the device's sysmon; unit noted in `energyUnit`.
        public var energy: Double?
        public var energyUnit: String?
        public init(takenAt: Date, process: String, pid: Int? = nil, cpuPercent: Double? = nil, energy: Double? = nil, energyUnit: String? = nil) {
            self.takenAt = takenAt; self.process = process; self.pid = pid; self.cpuPercent = cpuPercent; self.energy = energy; self.energyUnit = energyUnit
        }
    }

    public var schemaVersion: Int
    public var generatedAt: Date
    public var generator: String
    public var device: Device
    public var readings: [Reading]
    public var samples: [Sample]
    public var hotSpells: [HotSpell]
    public var findings: [Finding]
    public var hardwareTests: [HardwareTestResult]
    public var imports: [ImportRecord]
    public var redactions: [String]
    // Optional extensions (still v1).
    public var events: [LogEvent]?
    public var processSamples: [ProcessSample]?
    public var benchmark: BenchmarkResult?
    public var repairNotes: String?
    public var statuses: [WidgetSnapshot.AreaStatus]?
    /// The diagnosis as a case: hypotheses, state and earlier verdicts (plan §4b item 1).
    public var caseRecord: CaseRecord?
    /// Actions suggested or taken, with before/after and outcome (plan §5.14).
    public var actions: [ActionRecord]?
    /// Facts the person supplied (labelled user-supplied).
    public var userFacts: [UserFact]?
    /// What could not be determined and what would settle it (plan §4a item 9).
    public var couldNotDetermine: [String]?
    /// Advice catalogue version used.
    public var adviceVersion: Int?
    /// Companion only: per-process write rates from deltas between snapshots, and totals since start.
    public var processRates: [ProcessRate]?
    public var processTotals: [ProcessTotal]?

    public init(schemaVersion: Int = VitalsReport.currentVersion, generatedAt: Date, generator: String, device: Device, readings: [Reading] = [],
                samples: [Sample] = [], hotSpells: [HotSpell] = [], findings: [Finding] = [], hardwareTests: [HardwareTestResult] = [],
                imports: [ImportRecord] = [], redactions: [String] = [], events: [LogEvent]? = nil, processSamples: [ProcessSample]? = nil,
                benchmark: BenchmarkResult? = nil, repairNotes: String? = nil, statuses: [WidgetSnapshot.AreaStatus]? = nil,
                caseRecord: CaseRecord? = nil, actions: [ActionRecord]? = nil, userFacts: [UserFact]? = nil, couldNotDetermine: [String]? = nil,
                adviceVersion: Int? = nil) {
        self.schemaVersion = schemaVersion; self.generatedAt = generatedAt; self.generator = generator; self.device = device
        self.readings = readings; self.samples = samples; self.hotSpells = hotSpells; self.findings = findings
        self.hardwareTests = hardwareTests; self.imports = imports; self.redactions = redactions; self.events = events
        self.processSamples = processSamples; self.benchmark = benchmark; self.repairNotes = repairNotes; self.statuses = statuses
        self.caseRecord = caseRecord; self.actions = actions; self.userFacts = userFacts; self.couldNotDetermine = couldNotDetermine
        self.adviceVersion = adviceVersion
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, generator, device, readings, samples, hotSpells, findings, hardwareTests, imports, redactions
        case events, processSamples, benchmark, repairNotes, statuses, caseRecord, actions, userFacts, couldNotDetermine, adviceVersion, processRates, processTotals
    }

    /// Tolerant decoding: arrays missing from a (companion or older) file decode as empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        generator = try c.decodeIfPresent(String.self, forKey: .generator) ?? "unknown"
        device = try c.decode(Device.self, forKey: .device)
        readings = try c.decodeIfPresent([Reading].self, forKey: .readings) ?? []
        samples = try c.decodeIfPresent([Sample].self, forKey: .samples) ?? []
        hotSpells = try c.decodeIfPresent([HotSpell].self, forKey: .hotSpells) ?? []
        findings = try c.decodeIfPresent([Finding].self, forKey: .findings) ?? []
        hardwareTests = try c.decodeIfPresent([HardwareTestResult].self, forKey: .hardwareTests) ?? []
        imports = try c.decodeIfPresent([ImportRecord].self, forKey: .imports) ?? []
        redactions = try c.decodeIfPresent([String].self, forKey: .redactions) ?? []
        events = try c.decodeIfPresent([LogEvent].self, forKey: .events)
        processSamples = try c.decodeIfPresent([ProcessSample].self, forKey: .processSamples)
        benchmark = try c.decodeIfPresent(BenchmarkResult.self, forKey: .benchmark)
        repairNotes = try c.decodeIfPresent(String.self, forKey: .repairNotes)
        statuses = try c.decodeIfPresent([WidgetSnapshot.AreaStatus].self, forKey: .statuses)
        caseRecord = try c.decodeIfPresent(CaseRecord.self, forKey: .caseRecord)
        actions = try c.decodeIfPresent([ActionRecord].self, forKey: .actions)
        userFacts = try c.decodeIfPresent([UserFact].self, forKey: .userFacts)
        couldNotDetermine = try c.decodeIfPresent([String].self, forKey: .couldNotDetermine)
        adviceVersion = try c.decodeIfPresent(Int.self, forKey: .adviceVersion)
        processRates = try c.decodeIfPresent([ProcessRate].self, forKey: .processRates)
        processTotals = try c.decodeIfPresent([ProcessTotal].self, forKey: .processTotals)
    }
}

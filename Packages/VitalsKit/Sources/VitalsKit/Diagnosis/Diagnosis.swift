import Foundation

/// Everything the rules look at.
public struct DiagnosisInput: Sendable {
    public var readings: [Reading]
    public var samples: [Sample]
    public var batteryHealth: BatteryHealth?
    public var logEvents: [LogEvent]
    public var benchmark: BenchmarkResult?
    /// The current case (hypotheses from logs, companion captures and facts). Its hypotheses become findings,
    /// and an "expected and temporary" primary turns heat and drain findings into `expected`.
    public var caseResult: CaseResult?
    public var now: Date

    public init(readings: [Reading], samples: [Sample] = [], batteryHealth: BatteryHealth? = nil, logEvents: [LogEvent] = [],
                benchmark: BenchmarkResult? = nil, caseResult: CaseResult? = nil, now: Date = .now) {
        self.readings = readings; self.samples = samples; self.batteryHealth = batteryHealth; self.logEvents = logEvents
        self.benchmark = benchmark; self.caseResult = caseResult; self.now = now
    }

    func reading(_ id: String) -> Reading? { readings.first { $0.id == id } }
    func number(_ id: String) -> Double? { reading(id)?.value.number }
    func bool(_ id: String) -> Bool? { reading(id)?.value.bool }
    func text(_ id: String) -> String? { reading(id)?.value.text }
    func ev(_ id: String, _ text: String) -> Evidence {
        Evidence(text: text, provenance: reading(id)?.provenance ?? .measured, readingID: id, source: reading(id)?.source)
    }
}

/// Thresholds, kept together so they are easy to review and change.
public enum Thresholds {
    public static let lowBatteryPercent = 20.0
    public static let fastDrainPerHour = 20.0
    public static let wornCapacity = 80.0        // Apple's own "consider service" line for iPhone batteries
    public static let agingCapacity = 85.0
    public static let highCycleCount = 800
    /// Free space is judged mostly in absolute terms: iOS needs a few gigabytes of working room whatever
    /// the capacity, so a 1 TB phone with 20 GB free is fine while a 64 GB phone with 3 GB free is not.
    public static let storageProblemBytes = 3.0e9
    public static let storageAttentionBytes = 8.0e9
    public static let storageAttentionFraction = 0.05
    public static let memoryWarningsAttention = 3
    public static let longUptimeDays = 30.0
    public static let frequentCrashes = 5
}

/// Turns readings and history into a status and one plain sentence per area.
public enum DiagnosisEngine {
    public static func evaluate(_ input: DiagnosisInput) -> [AreaResult] {
        Area.allCases.map { evaluate($0, input) }
    }

    public static func evaluate(_ area: Area, _ input: DiagnosisInput) -> AreaResult {
        let readings = input.readings.filter { $0.area == area } + derivedReadings(area, input)
        var (status, sentence, findings): (Status, String, [Finding]) = switch area {
        case .battery: battery(input)
        case .heat: heat(input)
        case .storage: storage(input)
        case .memory: memory(input)
        case .network: network(input)
        case .software: software(input)
        }
        // Case hypotheses become findings in their area.
        let caseFindings = (input.caseResult?.hypotheses ?? []).filter { areaFor($0) == area }.map(finding(from:))
        findings += caseFindings
        if let primary = input.caseResult?.primary, primary.status == .expected, input.caseResult?.hypotheses.allSatisfy({ $0.status != .attention && $0.status != .problem }) == true {
            // Expected and temporary: heat and drain are explained, not faults. Safety-level findings stay.
            let explainable: Set<String> = ["heat.spells", "heat.now", "battery.fastDrain", "heat.cpuReports"]
            findings = findings.map { f in
                guard explainable.contains(f.id), !(f.id == "heat.now" && f.summary.hasPrefix(ThermalLevel.critical.label)) else { return f }
                var g = f; g.severity = .info; g.expected = true
                g.detail = [f.detail, "Explained by: \(primary.title.lowercased())."].compactMap { $0 }.joined(separator: " ")
                return g
            }
            if area == .heat || area == .battery, findings.contains(where: { $0.expected == true }) {
                let rest = findings.filter { $0.expected != true }
                status = statusFor(rest) == .good ? .expected : statusFor(rest)
                if status == .expected { sentence = primary.title + "." }
            }
        }
        if let top = caseFindings.max(by: { $0.severity < $1.severity }), top.severity > .info || top.expected == true {
            let s = statusFor(findings.filter { $0.expected != true })
            status = s == .good && findings.contains(where: { $0.expected == true }) ? .expected : max(status == .unknown ? s : status, s)
            if top.severity >= .attention || status == .expected { sentence = top.summary }
        }
        return AreaResult(area: area, status: status, sentence: sentence, readings: readings,
                          findings: findings.sorted { $0.severity > $1.severity }, couldNotDetermine: couldNotDetermine(area, input))
    }

    static func areaFor(_ h: Hypothesis) -> Area {
        h.id.hasPrefix("restart.") ? .software : .heat
    }

    static func finding(from h: Hypothesis) -> Finding {
        let sev: Severity = switch h.status {
        case .problem: .problem
        case .attention: .attention
        default: .info
        }
        return Finding(id: h.id, area: areaFor(h), severity: sev, summary: h.title,
                       detail: h.summary + (h.tier < .macDeveloper ? (h.tier.nextTierAdds.map { " " + $0 } ?? "") : ""),
                       evidence: h.reasoning, adviceKey: h.adviceKey, tier: h.tier, confidence: h.confidence, expected: h.status == .expected)
    }

    /// What could not be read for an area and what would settle it (plan §4a item 9).
    static func couldNotDetermine(_ area: Area, _ i: DiagnosisInput) -> [String] {
        var out: [String] = []
        switch area {
        case .battery:
            if i.batteryHealth?.effectiveMaxCapacity == nil {
                out.append("Maximum capacity: not readable by apps. Settings > Battery > Battery Health shows it; share a screenshot, or use the Mac companion.")
            }
            out.append("Which app used which share of the battery: only Settings > Battery shows it.")
        case .heat:
            out.append("Temperature in degrees: iOS gives apps only the pressure level.")
            out += (i.caseResult?.couldNotDetermine ?? []).filter { !$0.hasPrefix("Which app used") && !$0.hasPrefix("Battery temperature") }
        case .software:
            if i.logEvents.isEmpty { out.append("Crashes and restarts: share the newest daily analytics file to see them.") }
        default: break
        }
        return out
    }

    /// Inferred and log readings that belong in an area's detail screen.
    static func derivedReadings(_ area: Area, _ input: DiagnosisInput) -> [Reading] {
        var r: [Reading] = []
        let t = input.now
        switch area {
        case .battery:
            if let d = BatteryMath.drainPerHour(input.samples, now: t) {
                r.append(Reading(id: "battery.drainRate", area: .battery, label: "Drain rate (last 6 h, on battery)", value: .number(d), unit: "%/h",
                                 provenance: .inferred, source: "battery level change across Vitals' samples", takenAt: t))
            }
            if let c = BatteryMath.chargePerHour(input.samples, now: t) {
                r.append(Reading(id: "battery.chargeRate", area: .battery, label: "Charge rate (last 6 h)", value: .number(c), unit: "%/h",
                                 provenance: .inferred, source: "battery level change across Vitals' samples", takenAt: t))
            }
            if let h = input.batteryHealth {
                if let m = h.effectiveMaxCapacity {
                    r.append(Reading(id: "battery.maxCapacity", area: .battery, label: "Maximum capacity", value: .number(m.value), unit: "%",
                                     provenance: m.provenance, source: h.sourceFile, takenAt: h.asOf, unverified: true))
                }
                if let c = h.cycleCount {
                    r.append(Reading(id: "battery.cycleCount", area: .battery, label: "Charge cycles", value: .number(Double(c)),
                                     provenance: .parsedFromLog, source: h.sourceFile, takenAt: h.asOf, unverified: true))
                }
            }
        case .heat:
            let spells = HotSpellDetector.detect(input.samples).filter { $0.end >= t.addingTimeInterval(-86_400) }
            r.append(Reading(id: "heat.spells24h", area: .heat, label: "Hot spells, last 24 h", value: .number(Double(spells.count)),
                             provenance: .inferred, source: "Vitals' samples (serious or critical)", takenAt: t))
            let cov = Coverage.of(input.samples, from: t.addingTimeInterval(-86_400), to: t)
            r.append(Reading(id: "heat.samples24h", area: .heat, label: "Samples, last 24 h", value: .number(Double(cov.sampleCount)),
                             provenance: .measured, source: "Vitals' sample store", takenAt: t))
        default:
            break
        }
        return r
    }

    // MARK: Battery

    static func battery(_ i: DiagnosisInput) -> (Status, String, [Finding]) {
        var f: [Finding] = []
        let level = i.number("battery.level")
        let state = i.text("battery.state")
        let unplugged = state == ChargeState.unplugged.label

        if let level, level < Thresholds.lowBatteryPercent, unplugged {
            f.append(Finding(id: "battery.low", area: .battery, severity: .attention, summary: "Charge is low (\(Int(level))%).",
                             evidence: [i.ev("battery.level", "Battery level \(Int(level))%")]))
        }
        if let d = BatteryMath.drainPerHour(i.samples, now: i.now), d >= Thresholds.fastDrainPerHour {
            f.append(Finding(id: "battery.fastDrain", area: .battery, severity: .attention,
                             summary: "Draining fast: about \(Int(d.rounded()))% an hour on battery.",
                             detail: "Worked out from Vitals' own samples over the last six hours, so it reflects whatever the phone was doing then.",
                             evidence: [Evidence(text: "Drain rate \(Int(d.rounded()))%/h", provenance: .inferred, readingID: "battery.drainRate")]))
        }
        if let h = i.batteryHealth, let m = h.effectiveMaxCapacity {
            let pct = Int(m.value.rounded())
            let ev = Evidence(text: "Maximum capacity \(pct)% in \(h.sourceFile)", provenance: m.provenance, readingID: "battery.maxCapacity", source: h.sourceFile)
            if m.value < Thresholds.wornCapacity {
                f.append(Finding(id: "battery.worn", area: .battery, severity: .problem,
                                 summary: "Worn: holds about \(pct)% of its original charge.",
                                 detail: "Below 80% Apple suggests a battery service. A worn battery drains faster and can make the phone slow down under load.",
                                 evidence: [ev]))
            } else if m.value < Thresholds.agingCapacity {
                f.append(Finding(id: "battery.aging", area: .battery, severity: .attention,
                                 summary: "Ageing: holds about \(pct)% of its original charge.", evidence: [ev]))
            }
        }
        if let c = i.batteryHealth?.cycleCount, c >= Thresholds.highCycleCount {
            f.append(Finding(id: "battery.cycles", area: .battery, severity: .attention, summary: "\(c) charge cycles: a lot of use.",
                             evidence: [Evidence(text: "Cycle count \(c)", provenance: .parsedFromLog, readingID: "battery.cycleCount", source: i.batteryHealth?.sourceFile)]))
        }

        if level == nil && i.batteryHealth == nil {
            return (.unknown, "iOS did not report a battery level here, and wear has not been shared yet.", f)
        }
        let status = statusFor(f)
        let sentence: String
        if let top = f.max(by: { $0.severity < $1.severity }) {
            sentence = top.summary
        } else if let m = i.batteryHealth?.effectiveMaxCapacity {
            sentence = "Healthy: holds about \(Int(m.value.rounded()))% of its original charge."
        } else {
            sentence = "Charge looks normal. Wear is in Settings > Battery > Battery Health."
        }
        return (status, sentence, f)
    }

    // MARK: Heat

    static func heat(_ i: DiagnosisInput) -> (Status, String, [Finding]) {
        var f: [Finding] = []
        let raw = i.number("heat.thermalStateRaw").map { ThermalLevel(rawValue: Int($0)) ?? .nominal }
        let spells = HotSpellDetector.detect(i.samples).filter { $0.end >= i.now.addingTimeInterval(-86_400) }

        if let raw {
            switch raw {
            case .critical, .serious:
                f.append(Finding(id: "heat.now", area: .heat, severity: .problem, summary: "\(raw.label) right now. \(raw.meaning)",
                                 evidence: [i.ev("heat.thermalState", "Thermal state \(raw.label.lowercased())")]))
            case .fair:
                f.append(Finding(id: "heat.now", area: .heat, severity: .attention, summary: "Warm right now. \(raw.meaning)",
                                 evidence: [i.ev("heat.thermalState", "Thermal state fair")]))
            case .nominal: break
            }
        }
        if !spells.isEmpty {
            let unplugged = spells.filter { !$0.wasCharging }
            let long = spells.contains { $0.duration >= 30 * 60 && !$0.wasCharging }
            let severity: Severity = (spells.count >= 3 || long) ? .problem : .attention
            var summary = spells.count == 1 ? "One hot spell in the last 24 hours" : "\(spells.count) hot spells in the last 24 hours"
            summary += unplugged.isEmpty ? ", all while charging." : unplugged.count == spells.count ? ", none while charging." : "."
            f.append(Finding(id: "heat.spells", area: .heat, severity: severity, summary: summary,
                             detail: "Share that day's analytics file or reports to see which processes were busy then.",
                             evidence: spells.map { s in
                                 Evidence(text: "\(s.peak.label) from \(s.start.formatted(date: .omitted, time: .shortened)) for \(DurationFormatting.string(seconds: max(s.duration, 60)))\(s.wasCharging ? ", charging" : "")",
                                          provenance: .inferred, readingID: "heat.spells24h")
                             }))
        }
        let culprits = i.logEvents.filter { $0.kind == .cpuResource && $0.timestamp >= i.now.addingTimeInterval(-7 * 86_400) }
        if !culprits.isEmpty {
            let names = Dictionary(grouping: culprits, by: \.process).sorted { $0.value.count > $1.value.count }.prefix(3).map { ProcessGlossary.friendlyName($0.key) }
            f.append(Finding(id: "heat.cpuReports", area: .heat, severity: .attention,
                             summary: "iOS flagged heavy CPU use by \(ListFormatter.localizedString(byJoining: names)) this week.",
                             evidence: culprits.prefix(5).map { Evidence(text: "\(ProcessGlossary.display($0.process)): \($0.detail ?? $0.kind.label)", provenance: .parsedFromLog, source: $0.importID) }))
        }

        guard raw != nil else { return (.unknown, "iOS did not report a thermal state.", f) }
        let status = statusFor(f)
        let sentence: String
        if let top = f.max(by: { $0.severity < $1.severity }) {
            sentence = top.summary
        } else if Coverage.of(i.samples, from: i.now.addingTimeInterval(-86_400), to: i.now).sampleCount < 4 {
            sentence = "Normal right now. Vitals needs a day of samples to spot hot spells."
        } else {
            sentence = "Normal, with no hot spells in the last 24 hours."
        }
        return (status, sentence, f)
    }

    // MARK: Storage

    static func storage(_ i: DiagnosisInput) -> (Status, String, [Finding]) {
        guard let total = i.number("storage.total"), total > 0,
              let free = i.number("storage.freeImportant") ?? i.number("storage.free") else {
            return (.unknown, "iOS did not report storage capacity.", [])
        }
        let fraction = free / total
        let freeText = ByteFormatting.string(free)
        let ev = i.ev(i.reading("storage.freeImportant") != nil ? "storage.freeImportant" : "storage.free", "\(freeText) free of \(ByteFormatting.string(total))")
        if free < Thresholds.storageProblemBytes {
            return (.problem, "Nearly full: \(freeText) free. iOS slows down and cannot install updates when space runs out.",
                    [Finding(id: "storage.full", area: .storage, severity: .problem, summary: "Nearly full: \(freeText) free.",
                             detail: "iOS needs working space for caches, photos processing and updates. Below a few gigabytes, apps reload more and updates fail.",
                             evidence: [ev])])
        }
        if fraction < Thresholds.storageAttentionFraction || free < Thresholds.storageAttentionBytes {
            return (.attention, "Getting full: \(freeText) free.",
                    [Finding(id: "storage.low", area: .storage, severity: .attention, summary: "Getting full: \(freeText) free.", evidence: [ev])])
        }
        return (.good, "\(freeText) free. Plenty of room; space is not slowing the phone.", [])
    }

    // MARK: Memory and performance

    static func memory(_ i: DiagnosisInput) -> (Status, String, [Finding]) {
        var f: [Finding] = []
        if let w = i.number("memory.warnings"), Int(w) >= Thresholds.memoryWarningsAttention {
            f.append(Finding(id: "memory.warnings", area: .memory, severity: .attention, summary: "Vitals itself was warned about low memory \(Int(w)) times.",
                             evidence: [i.ev("memory.warnings", "\(Int(w)) warnings")]))
        }
        if let cores = i.number("memory.cores"), let active = i.number("memory.activeCores"), active < cores {
            f.append(Finding(id: "memory.cores", area: .memory, severity: .attention,
                             summary: "Only \(Int(active)) of \(Int(cores)) CPU cores active.",
                             detail: "iOS parks cores to save power or cool down.",
                             evidence: [i.ev("memory.activeCores", "\(Int(active)) active cores")]))
        }
        let jetsams = i.logEvents.filter { $0.kind == .jetsam || $0.kind == .jetsamLargest }
            .filter { $0.timestamp >= i.now.addingTimeInterval(-7 * 86_400) }
        let jetsamReports = Set(jetsams.map(\.importID)).count
        if jetsamReports >= 3 {
            f.append(Finding(id: "memory.jetsam", area: .memory, severity: .attention,
                             summary: "\(jetsamReports) memory-pressure reports this week: apps are being closed to free memory.",
                             evidence: jetsams.prefix(5).map { Evidence(text: "\(ProcessGlossary.display($0.process)) \($0.kind.label.lowercased())", provenance: .parsedFromLog, source: $0.importID) }))
        }
        if let b = i.benchmark, let verdict = b.verdict, verdict == .belowRange {
            f.append(Finding(id: "memory.benchmark", area: .memory, severity: .attention,
                             summary: "The last benchmark scored below the usual range for this model.",
                             detail: "Heat, Low Power Mode and a worn battery all lower scores.",
                             evidence: [Evidence(text: b.summaryLine, provenance: .measured)]))
        }
        let status = statusFor(f)
        let mem = i.number("memory.physical").map { ByteFormatting.memory($0) } ?? "Unknown"
        let sentence = f.max(by: { $0.severity < $1.severity })?.summary ?? "\(mem) of memory, no signs of memory pressure seen."
        return (status, sentence, f)
    }

    // MARK: Network

    static func network(_ i: DiagnosisInput) -> (Status, String, [Finding]) {
        var f: [Finding] = []
        let status = i.text("network.status")
        if status == "No connection" {
            f.append(Finding(id: "network.none", area: .network, severity: .problem, summary: "No network connection.",
                             evidence: [i.ev("network.status", "Path unsatisfied")]))
        }
        if i.bool("network.constrained") == true {
            f.append(Finding(id: "network.lowData", area: .network, severity: .attention, summary: "Low Data Mode is on, so apps hold back on data.",
                             evidence: [i.ev("network.constrained", "Path is constrained")]))
        }
        if i.bool("network.vpn") == true {
            f.append(Finding(id: "network.vpn", area: .network, severity: .info, summary: "A VPN or tunnel looks active. It can slow connections and use battery.",
                             evidence: [i.ev("network.vpn", "Tunnel interface with an address")]))
        }
        if i.bool("network.proxy") == true {
            f.append(Finding(id: "network.proxy", area: .network, severity: .attention, summary: "A proxy is configured. Traffic goes through it.",
                             evidence: [i.ev("network.proxy", "Proxy settings present")]))
        }
        if status == nil { return (.unknown, "Network status was not available.", f) }
        let s = statusFor(f)
        let using = i.text("network.interfaces") ?? ""
        let sentence = f.first(where: { $0.severity != .info })?.summary ?? "Connected over \(using)." + (f.isEmpty ? "" : " " + f[0].summary)
        return (s, sentence, f)
    }

    // MARK: Software

    static func software(_ i: DiagnosisInput) -> (Status, String, [Finding]) {
        var f: [Finding] = []
        let osText = i.text("software.os") ?? ""
        let version = osText.split(separator: " ").last.map(String.init) ?? ""
        if let latest = Catalog.latestOS, !version.isEmpty, compareVersions(version, latest) == .orderedAscending {
            f.append(Finding(id: "software.update", area: .software, severity: .attention,
                             summary: "iOS \(version) is behind \(latest), the newest Vitals knows of (as of \(Catalog.osTableDate ?? "this app version")).",
                             detail: "Vitals does not check online. Your phone may not support the newest version; Settings > General > Software Update says for sure.",
                             evidence: [i.ev("software.os", osText)]))
        }
        if let up = i.number("software.uptime"), up / 86_400 >= Thresholds.longUptimeDays {
            f.append(Finding(id: "software.uptime", area: .software, severity: .info,
                             summary: "Running \(Int(up / 86_400)) days without a restart. A restart clears stuck background work.",
                             evidence: [i.ev("software.uptime", DurationFormatting.string(seconds: up))]))
        }
        let week = i.logEvents.filter { $0.timestamp >= i.now.addingTimeInterval(-7 * 86_400) }
        let crashesByApp = Dictionary(grouping: week.filter { $0.kind == .crash }, by: \.process)
        for (app, events) in crashesByApp where events.count >= Thresholds.frequentCrashes {
            f.append(Finding(id: "software.crash.\(app)", area: .software, severity: .attention,
                             summary: "\(app) crashed \(events.count) times this week.",
                             evidence: events.prefix(3).map { Evidence(text: "\($0.timestamp.formatted()) \($0.detail ?? "")", provenance: .parsedFromLog, source: $0.importID) }))
        }
        let panics = week.filter { $0.kind == .panic }
        if !panics.isEmpty {
            f.append(Finding(id: "software.panic", area: .software, severity: .problem,
                             summary: panics.count == 1 ? "The phone restarted unexpectedly once this week." : "The phone restarted unexpectedly \(panics.count) times this week.",
                             detail: "Repeated unexpected restarts can point to hardware. Keep the panic reports for Apple.",
                             evidence: panics.map { Evidence(text: "\($0.timestamp.formatted()) \($0.detail ?? "")", provenance: .parsedFromLog, source: $0.importID) }))
        }
        if i.bool("software.simulator") == true {
            f.append(Finding(id: "software.simulator", area: .software, severity: .info,
                             summary: "Running in the Simulator: readings describe the Mac, not a phone.",
                             evidence: [i.ev("software.simulator", "SIMULATOR_MODEL_IDENTIFIER set")]))
        }
        if osText.isEmpty { return (.unknown, "System details were not available.", f) }
        let s = statusFor(f)
        let model = i.text("software.model") ?? ""
        let sentence = f.first(where: { $0.severity != .info })?.summary ?? "\(model) on \(osText), up to date as far as Vitals knows."
        return (s, sentence, f)
    }

    static func statusFor(_ findings: [Finding]) -> Status {
        switch findings.map(\.severity).max() {
        case .problem: .problem
        case .attention: .attention
        default: .good
        }
    }
}

extension DiagnosisEngine {
    /// A hypothesis as a finding, for showing advice, tier and confidence.
    public static func findingForDisplay(_ h: Hypothesis) -> Finding { finding(from: h) }
}

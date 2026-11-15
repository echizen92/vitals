import Foundation

/// Personalised ways to run better, for a phone with or without faults (plan §5.14). Only items with
/// evidence on this phone appear; there is no generic tip list.
public struct OptimiseItem: Codable, Sendable, Hashable, Identifiable {
    public enum Topic: String, Codable, Sendable, CaseIterable {
        case battery, storage, network, performance, background
        public var label: String {
            switch self {
            case .battery: "Battery longevity"
            case .storage: "Storage"
            case .network: "Network"
            case .performance: "Performance"
            case .background: "Background activity"
            }
        }
    }
    public var id: String
    public var topic: Topic
    public var title: String
    public var because: Evidence
    public var actionIDs: [String]
}

public enum OptimiseEngine {
    public static func items(checkup: Checkup?, samples: [Sample], events: [LogEvent], days: [AnalyticsDay],
                             health: BatteryHealth?, benchmark: BenchmarkResult?, now: Date = .now) -> [OptimiseItem] {
        var out: [OptimiseItem] = []
        let r = checkup?.readings ?? []
        func num(_ id: String) -> Double? { r.first { $0.id == id }?.value.number }
        func bool(_ id: String) -> Bool? { r.first { $0.id == id }?.value.bool }
        let week = samples.filter { $0.takenAt >= now.addingTimeInterval(-7 * 86_400) && $0.source != .fixture }

        // Battery: hot while charging; long hours held full; many cycles.
        let chargingSpells = HotSpellDetector.detect(week).filter(\.wasCharging)
        if !chargingSpells.isEmpty {
            out.append(OptimiseItem(id: "opt.heatCharging", topic: .battery, title: "Ran hot while charging",
                                    because: Evidence(text: "\(chargingSpells.count) hot spell\(chargingSpells.count == 1 ? "" : "s") while plugged in this week", provenance: .inferred),
                                    actionIDs: ["manual.heatWhileCharging", "manual.chargeLimit"]))
        }
        let fullSamples = week.filter { $0.charge == .full }
        if fullSamples.count >= 12 {
            out.append(OptimiseItem(id: "opt.heldFull", topic: .battery, title: "Often sits at 100% on the charger",
                                    because: Evidence(text: "\(fullSamples.count) samples at full this week", provenance: .measured),
                                    actionIDs: ["manual.chargeLimit", "relief.protectBattery"]))
        }
        if let c = health?.cycleCount ?? days.compactMap(\.cycleCount).last, c >= 300 {
            out.append(OptimiseItem(id: "opt.cycles", topic: .battery, title: "\(c) charge cycles so far",
                                    because: Evidence(text: "Cycle count \(c)", provenance: .parsedFromLog), actionIDs: ["manual.chargeLimit", "manual.batteryHealthCheck"]))
        }
        if health?.effectiveMaxCapacity == nil {
            out.append(OptimiseItem(id: "opt.capacityUnknown", topic: .battery, title: "Vitals cannot see battery wear yet",
                                    because: Evidence(text: "Maximum capacity is only in Settings > Battery > Battery Health", provenance: .inferred),
                                    actionIDs: ["manual.batteryHealthCheck"]))
        }
        // Storage housekeeping when under 20% free.
        if let total = num("storage.total"), let free = num("storage.freeImportant") ?? num("storage.free"), total > 0, free / total < 0.2 {
            out.append(OptimiseItem(id: "opt.storage", topic: .storage, title: "\(ByteFormatting.string(free)) free",
                                    because: Evidence(text: "\(Int(free / total * 100))% of \(ByteFormatting.string(total)) free", provenance: .measured),
                                    actionIDs: ["vitals.photoCleanup", "guided.offloadApps", "guided.messagesAttachments"]))
        }
        // Network.
        if bool("network.constrained") == true {
            out.append(OptimiseItem(id: "opt.lowData", topic: .network, title: "Low Data Mode is holding back sync and backups",
                                    because: Evidence(text: "Path is constrained", provenance: .measured), actionIDs: ["manual.lowDataMode"]))
        }
        if bool("network.vpn") == true || bool("network.proxy") == true {
            out.append(OptimiseItem(id: "opt.vpn", topic: .network, title: "A VPN or proxy adds overhead",
                                    because: Evidence(text: "Tunnel or proxy detected", provenance: .inferred), actionIDs: ["manual.vpnCheck"]))
        }
        // Performance.
        if let os = r.first(where: { $0.id == "software.os" })?.value.text, let latest = Catalog.latestOS,
           let v = os.split(separator: " ").last.map(String.init), compareVersions(v, latest) == .orderedAscending {
            out.append(OptimiseItem(id: "opt.update", topic: .performance, title: "An iOS update may be waiting",
                                    because: Evidence(text: "\(os), newest known \(latest)", provenance: .inferred), actionIDs: ["manual.update"]))
        }
        if let up = num("software.uptime"), up > 14 * 86_400 {
            out.append(OptimiseItem(id: "opt.uptime", topic: .performance, title: "Running \(Int(up / 86_400)) days since a restart",
                                    because: Evidence(text: "Uptime \(DurationFormatting.string(seconds: up))", provenance: .measured), actionIDs: ["guided.restart", "relief.restart"]))
        }
        if benchmark?.verdict == .belowRange {
            out.append(OptimiseItem(id: "opt.benchmark", topic: .performance, title: "Benchmark below the usual range",
                                    because: Evidence(text: benchmark!.summaryLine, provenance: .measured), actionIDs: ["guided.coolDown", "manual.batteryHealthCheck"]))
        }
        // Background activity: third-party apps flagged or widgets over budget.
        let thirdParty = events.filter { [.powerException, .cpuResource, .diskWrites].contains($0.kind) && ProcessGlossary.entry(for: $0.process) == nil }
            .filter { $0.timestamp >= now.addingTimeInterval(-7 * 86_400) }
        if let top = Dictionary(grouping: thirdParty, by: \.process).max(by: { $0.value.count < $1.value.count }) {
            out.append(OptimiseItem(id: "opt.background.\(top.key)", topic: .background, title: "\(top.key) works hard in the background",
                                    because: Evidence(text: "\(top.value.count) report\(top.value.count == 1 ? "" : "s"): \(top.value.first?.detail ?? "")", provenance: .parsedFromLog),
                                    actionIDs: ["guided.backgroundRefresh", "guided.locationReview"]))
        }
        if days.isEmpty {
            out.append(OptimiseItem(id: "opt.shareAnalytics", topic: .background, title: "See what runs in the background",
                                    because: Evidence(text: "No daily analytics file shared yet", provenance: .inferred), actionIDs: ["manual.shareAnalytics"]))
        }
        return out
    }
}

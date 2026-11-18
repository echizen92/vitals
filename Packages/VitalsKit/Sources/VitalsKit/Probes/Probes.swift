import Foundation

/// Bundled lookup tables (no network).
public enum Catalog {
    struct Models: Decodable { let models: [String: String] }
    struct OSTable: Decodable { let asOf: String; let latest: String }

    static let models: [String: String] = {
        guard let url = Bundle.module.url(forResource: "models", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(Models.self, from: data) else { return [:] }
        return m.models
    }()

    static let osTable: OSTable? = {
        guard let url = Bundle.module.url(forResource: "os-versions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OSTable.self, from: data)
    }()

    public static func modelName(for identifier: String) -> String? { models[identifier] }
    public static var latestOS: String? { osTable?.latest }
    public static var osTableDate: String? { osTable?.asOf }
    /// The table's date for people: day and short month in the reader's locale ("15 Nov", "Nov 15").
    public static var osTableDateText: String? { osTableDate.flatMap { dayMonth(isoDay: $0) } }

    /// "2026-11-15" -> "15 Nov" (locale-aware). Nil when the text is not a yyyy-MM-dd day.
    public static func dayMonth(isoDay: String, locale: Locale = .current) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: isoDay) else { return nil }
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        style.locale = locale
        style.timeZone = TimeZone(identifier: "UTC")!
        return d.formatted(style)
    }

    /// iPhone Duo identifiers. Taken from the Xcode 27.2 simulator profile; confirm on the real phone.
    public static func isDuo(_ identifier: String) -> Bool {
        modelName(for: identifier)?.contains("Duo") == true
    }
}

/// Compares dotted version strings numerically ("27.10" > "27.9").
public func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
}

/// Pure functions from raw values to readings. One per area, so each can be tested on its own.
public enum Probes {
    public static func thermal(_ level: ThermalLevel, at t: Date) -> [Reading] {
        [Reading(id: "heat.thermalState", area: .heat, label: "Thermal state", value: .text(level.label),
                 provenance: .measured, source: "ProcessInfo.thermalState", takenAt: t),
         Reading(id: "heat.thermalStateRaw", area: .heat, label: "Thermal state (raw)", value: .number(Double(level.rawValue)),
                 provenance: .measured, source: "ProcessInfo.thermalState (0 nominal … 3 critical)", takenAt: t)]
    }

    public static func battery(_ raw: BatteryRaw, at t: Date) -> [Reading] {
        var r: [Reading] = []
        if let level = raw.level {
            r.append(Reading(id: "battery.level", area: .battery, label: "Battery level", value: .number(level * 100), unit: "%",
                             provenance: .measured, source: "UIDevice.batteryLevel", takenAt: t))
        }
        r.append(Reading(id: "battery.state", area: .battery, label: "Charging state", value: .text(raw.state.label),
                         provenance: .measured, source: "UIDevice.batteryState", takenAt: t))
        r.append(Reading(id: "battery.lowPowerMode", area: .battery, label: "Low Power Mode", value: .bool(raw.lowPowerMode),
                         provenance: .measured, source: "ProcessInfo.isLowPowerModeEnabled", takenAt: t))
        return r
    }

    public static func storage(_ raw: StorageRaw, at t: Date) -> [Reading] {
        var r: [Reading] = []
        let src = "URLResourceValues"
        if let total = raw.total {
            r.append(Reading(id: "storage.total", area: .storage, label: "Capacity", value: .number(Double(total)), unit: "bytes",
                             provenance: .measured, source: "\(src).volumeTotalCapacity", takenAt: t))
        }
        if let free = raw.free {
            r.append(Reading(id: "storage.free", area: .storage, label: "Free now", value: .number(Double(free)), unit: "bytes",
                             provenance: .measured, source: "\(src).volumeAvailableCapacity", takenAt: t))
        }
        if let imp = raw.freeForImportant {
            r.append(Reading(id: "storage.freeImportant", area: .storage, label: "Free for important use", value: .number(Double(imp)), unit: "bytes",
                             provenance: .measured, source: "\(src).volumeAvailableCapacityForImportantUsage", takenAt: t))
        }
        if let opp = raw.freeForOpportunistic {
            r.append(Reading(id: "storage.freeOpportunistic", area: .storage, label: "Free for optional use", value: .number(Double(opp)), unit: "bytes",
                             provenance: .measured, source: "\(src).volumeAvailableCapacityForOpportunisticUsage", takenAt: t))
        }
        if let total = raw.total, let free = raw.freeForImportant ?? raw.free, total > 0 {
            r.append(Reading(id: "storage.used", area: .storage, label: "Used", value: .number(Double(total - free)), unit: "bytes",
                             provenance: .inferred, source: "capacity − free for important use", takenAt: t))
            r.append(Reading(id: "storage.freePercent", area: .storage, label: "Free", value: .number(Double(free) / Double(total) * 100), unit: "%",
                             provenance: .inferred, source: "free for important use ÷ capacity", takenAt: t))
        }
        return r
    }

    public static func memory(_ raw: MemoryRaw, at t: Date) -> [Reading] {
        var r: [Reading] = [
            Reading(id: "memory.physical", area: .memory, label: "Physical memory", value: .number(Double(raw.physical)), unit: "bytes",
                    provenance: .measured, source: "ProcessInfo.physicalMemory", takenAt: t),
            Reading(id: "memory.cores", area: .memory, label: "CPU cores", value: .number(Double(raw.processorCount)),
                    provenance: .measured, source: "ProcessInfo.processorCount", takenAt: t),
            Reading(id: "memory.activeCores", area: .memory, label: "Active CPU cores", value: .number(Double(raw.activeProcessorCount)),
                    provenance: .measured, source: "ProcessInfo.activeProcessorCount", takenAt: t),
            Reading(id: "memory.warnings", area: .memory, label: "Memory warnings Vitals received", value: .number(Double(raw.warningsSeen)),
                    provenance: .measured, source: "UIApplication.didReceiveMemoryWarningNotification (counted by Vitals)", takenAt: t),
        ]
        if let f = raw.appFootprint {
            r.append(Reading(id: "memory.appFootprint", area: .memory, label: "Vitals' own memory use", value: .number(Double(f)), unit: "bytes",
                             provenance: .measured, source: "task_info(TASK_VM_INFO).phys_footprint", takenAt: t))
        }
        if let a = raw.appAvailable {
            r.append(Reading(id: "memory.appAvailable", area: .memory, label: "Memory still available to an app", value: .number(Double(a)), unit: "bytes",
                             provenance: .measured, source: "os_proc_available_memory()", takenAt: t))
        }
        if let since = raw.warningsSince {
            r.append(Reading(id: "memory.warningsSince", area: .memory, label: "Counting warnings since",
                             value: .text(since.formatted(date: .abbreviated, time: .shortened)),
                             provenance: .measured, source: "Vitals", takenAt: t))
        }
        return r
    }

    public static func software(_ raw: SoftwareRaw, at t: Date) -> [Reading] {
        var r: [Reading] = [
            Reading(id: "software.model", area: .software, label: "Model",
                    value: .text(Catalog.modelName(for: raw.modelIdentifier) ?? raw.modelIdentifier),
                    provenance: .measured, source: raw.isSimulator ? "SIMULATOR_MODEL_IDENTIFIER" : "sysctl hw.machine", takenAt: t),
            Reading(id: "software.modelIdentifier", area: .software, label: "Model identifier", value: .text(raw.modelIdentifier),
                    provenance: .measured, source: raw.isSimulator ? "SIMULATOR_MODEL_IDENTIFIER" : "sysctl hw.machine", takenAt: t),
            Reading(id: "software.os", area: .software, label: "System", value: .text("\(raw.osName) \(raw.osVersion)"),
                    provenance: .measured, source: "ProcessInfo.operatingSystemVersion", takenAt: t),
            Reading(id: "software.uptime", area: .software, label: "Time since restart", value: .number(raw.uptime), unit: "s",
                    provenance: .measured, source: "ProcessInfo.systemUptime", takenAt: t),
        ]
        if let b = raw.osBuild {
            r.append(Reading(id: "software.build", area: .software, label: "Build", value: .text(b),
                             provenance: .measured, source: "sysctl kern.osversion", takenAt: t))
        }
        if let a = raw.appDataBytes {
            r.append(Reading(id: "software.appData", area: .software, label: "Vitals' own data", value: .number(Double(a)), unit: "bytes",
                             provenance: .measured, source: "file sizes in Vitals' containers", takenAt: t))
        }
        if raw.isSimulator {
            r.append(Reading(id: "software.simulator", area: .software, label: "Running in the Simulator", value: .bool(true),
                             provenance: .measured, source: "process environment", takenAt: t))
        }
        if let name = raw.deviceName {
            r.append(Reading(id: "software.deviceName", area: .software, label: "Device name", value: .text(name),
                             provenance: .measured, source: "UIDevice.name (generic unless the app has the entitlement)", takenAt: t))
        }
        return r
    }

    public static func network(_ raw: NetworkRaw, at t: Date) -> [Reading] {
        let src = "NWPathMonitor"
        let status: String = switch raw.status {
        case .satisfied: "Connected"
        case .unsatisfied: "No connection"
        case .requiresConnection: "Waiting to connect"
        case .unknown: "Unknown"
        }
        return [
            Reading(id: "network.status", area: .network, label: "Connection", value: .text(status), provenance: .measured, source: "\(src).status", takenAt: t),
            Reading(id: "network.interfaces", area: .network, label: "Using",
                    value: .text(raw.interfaces.isEmpty ? "None" : raw.interfaces.map(\.label).joined(separator: ", ")),
                    provenance: .measured, source: "\(src).usesInterfaceType", takenAt: t),
            Reading(id: "network.constrained", area: .network, label: "Low Data Mode", value: .bool(raw.isConstrained), provenance: .measured, source: "\(src).isConstrained", takenAt: t),
            Reading(id: "network.expensive", area: .network, label: "Metered (cellular or hotspot)", value: .bool(raw.isExpensive), provenance: .measured, source: "\(src).isExpensive", takenAt: t),
            Reading(id: "network.ipv6", area: .network, label: "IPv6", value: .bool(raw.supportsIPv6), provenance: .measured, source: "\(src).supportsIPv6", takenAt: t),
            Reading(id: "network.dns", area: .network, label: "DNS available", value: .bool(raw.supportsDNS), provenance: .measured, source: "\(src).supportsDNS", takenAt: t),
            Reading(id: "network.vpn", area: .network, label: "VPN or tunnel", value: .bool(raw.vpnLikely), provenance: .inferred,
                    source: "getifaddrs (utun/ipsec with an address) and NWPath .other", takenAt: t),
            Reading(id: "network.proxy", area: .network, label: "Proxy configured", value: .bool(raw.proxyConfigured), provenance: .measured,
                    source: "CFNetworkCopySystemProxySettings", takenAt: t),
        ]
    }

    public static func display(_ raw: DisplayRaw, at t: Date) -> [Reading] {
        [Reading(id: "software.display", area: .software, label: "Display (this scene)",
                 value: .text("\(Int(raw.widthPoints)) × \(Int(raw.heightPoints)) pt @\(Int(raw.scale))x"),
                 provenance: .measured, source: "UIWindowScene.screen", takenAt: t),
         Reading(id: "software.refresh", area: .software, label: "Maximum refresh rate", value: .number(Double(raw.maxFramesPerSecond)), unit: "Hz",
                 provenance: .measured, source: "UIScreen.maximumFramesPerSecond", takenAt: t)]
    }
}

import Foundation
import VitalsKit

/// Named states for the simulator, which cannot produce real heat, battery or storage pressure.
/// Chosen in Settings > Simulator state, or at launch with `-inject <name>`. Everything shown while
/// injecting is labelled "Injected values" in the UI so it can never pass for a real reading.
enum InjectionPresets: String, CaseIterable, Identifiable {
    case healthy, warm, hot, critical, lowStorage, lowBattery, offline

    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthy: "Healthy phone"
        case .warm: "Warm (fair)"
        case .hot: "Hot (serious), unplugged"
        case .critical: "Very hot (critical), charging"
        case .lowStorage: "Storage nearly full"
        case .lowBattery: "Low battery, Low Power Mode"
        case .offline: "No network"
        }
    }

    var source: FixedSystemSource {
        var s = FixedSystemSource.healthy
        s.delayPerProbe = 0.35
        s.softwareRaw.modelIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? s.softwareRaw.modelIdentifier
        switch self {
        case .healthy: break
        case .warm: s.thermalLevel = .fair
        case .hot:
            s.thermalLevel = .serious
            s.batteryRaw = BatteryRaw(level: 0.41, state: .unplugged, lowPowerMode: false)
        case .critical:
            s.thermalLevel = .critical
            s.batteryRaw = BatteryRaw(level: 0.63, state: .charging, lowPowerMode: false)
            s.memoryRaw.activeProcessorCount = 4
        case .lowStorage:
            s.storageRaw = StorageRaw(total: 128_000_000_000, free: 1_200_000_000, freeForImportant: 2_100_000_000, freeForOpportunistic: 900_000_000)
        case .lowBattery:
            s.batteryRaw = BatteryRaw(level: 0.12, state: .unplugged, lowPowerMode: true)
        case .offline:
            s.networkRaw = NetworkRaw(status: .unsatisfied, interfaces: [], isConstrained: false, isExpensive: false, supportsIPv4: false,
                                      supportsIPv6: false, supportsDNS: false, vpnLikely: false, proxyConfigured: false)
        }
        return s
    }

    static func fromLaunchArguments() -> FixedSystemSource? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-inject"), i + 1 < args.count, let p = InjectionPresets(rawValue: args[i + 1]) else { return nil }
        return p.source
    }
}

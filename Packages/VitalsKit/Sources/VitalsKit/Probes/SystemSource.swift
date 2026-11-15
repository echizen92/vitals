import Foundation

// Raw values from public APIs, one struct per area. Probes turn these into `Reading`s.
// Keeping raw values separate lets tests and the simulator inject any state (a hot phone,
// a full disk) without touching the code that interprets them.

public struct BatteryRaw: Sendable, Hashable, Codable {
    /// 0...1, nil when `UIDevice.batteryLevel` is -1 (the simulator, or monitoring unavailable).
    public var level: Double?
    public var state: ChargeState
    public var lowPowerMode: Bool
    public init(level: Double?, state: ChargeState, lowPowerMode: Bool) {
        self.level = level; self.state = state; self.lowPowerMode = lowPowerMode
    }
}

public struct StorageRaw: Sendable, Hashable, Codable {
    public var total: Int64?
    /// `volumeAvailableCapacityKey`: free right now.
    public var free: Int64?
    /// `volumeAvailableCapacityForImportantUsageKey`: what iOS would make room for if the person needed it (purges caches).
    public var freeForImportant: Int64?
    /// `volumeAvailableCapacityForOpportunisticUsageKey`.
    public var freeForOpportunistic: Int64?
    public init(total: Int64?, free: Int64?, freeForImportant: Int64?, freeForOpportunistic: Int64?) {
        self.total = total; self.free = free; self.freeForImportant = freeForImportant; self.freeForOpportunistic = freeForOpportunistic
    }
}

public struct MemoryRaw: Sendable, Hashable, Codable {
    public var physical: UInt64
    /// This app's own footprint (`task_vm_info.phys_footprint`).
    public var appFootprint: UInt64?
    /// `os_proc_available_memory()`: how much more this app could use before iOS stops it. iOS only.
    public var appAvailable: UInt64?
    public var processorCount: Int
    public var activeProcessorCount: Int
    /// Memory-pressure warnings Vitals itself received, and since when it has been counting.
    public var warningsSeen: Int
    public var warningsSince: Date?
    public init(physical: UInt64, appFootprint: UInt64?, appAvailable: UInt64?, processorCount: Int, activeProcessorCount: Int,
                warningsSeen: Int, warningsSince: Date?) {
        self.physical = physical; self.appFootprint = appFootprint; self.appAvailable = appAvailable
        self.processorCount = processorCount; self.activeProcessorCount = activeProcessorCount
        self.warningsSeen = warningsSeen; self.warningsSince = warningsSince
    }
}

public struct SoftwareRaw: Sendable, Hashable, Codable {
    /// e.g. `iPhone17,1`; on the simulator the simulated model's identifier.
    public var modelIdentifier: String
    public var osName: String
    public var osVersion: String
    public var osBuild: String?
    public var uptime: TimeInterval
    public var bootTime: Date?
    public var isSimulator: Bool
    /// Bytes used by Vitals' own data (app container plus shared group container).
    public var appDataBytes: Int64?
    public var deviceName: String?
    public init(modelIdentifier: String, osName: String, osVersion: String, osBuild: String?, uptime: TimeInterval,
                bootTime: Date?, isSimulator: Bool, appDataBytes: Int64?, deviceName: String?) {
        self.modelIdentifier = modelIdentifier; self.osName = osName; self.osVersion = osVersion; self.osBuild = osBuild
        self.uptime = uptime; self.bootTime = bootTime; self.isSimulator = isSimulator; self.appDataBytes = appDataBytes
        self.deviceName = deviceName
    }
}

public enum Interface: String, Codable, Sendable, CaseIterable {
    case wifi, cellular, wired, loopback, other
    public var label: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wired: "Wired"
        case .loopback: "Loopback"
        case .other: "Other (VPN or tunnel)"
        }
    }
}

public struct NetworkRaw: Sendable, Hashable, Codable {
    public enum PathStatus: String, Codable, Sendable { case satisfied, unsatisfied, requiresConnection, unknown }
    public var status: PathStatus
    public var interfaces: [Interface]
    public var isConstrained: Bool
    public var isExpensive: Bool
    public var supportsIPv4: Bool
    public var supportsIPv6: Bool
    public var supportsDNS: Bool
    /// A `utun`/`ipsec` interface is up, or the path uses an "other" interface.
    public var vpnLikely: Bool
    /// HTTP/HTTPS proxy or PAC configured (`CFNetworkCopySystemProxySettings`).
    public var proxyConfigured: Bool
    public init(status: PathStatus, interfaces: [Interface], isConstrained: Bool, isExpensive: Bool, supportsIPv4: Bool,
                supportsIPv6: Bool, supportsDNS: Bool, vpnLikely: Bool, proxyConfigured: Bool) {
        self.status = status; self.interfaces = interfaces; self.isConstrained = isConstrained; self.isExpensive = isExpensive
        self.supportsIPv4 = supportsIPv4; self.supportsIPv6 = supportsIPv6; self.supportsDNS = supportsDNS
        self.vpnLikely = vpnLikely; self.proxyConfigured = proxyConfigured
    }
}

public struct DisplayRaw: Sendable, Hashable, Codable {
    public var widthPoints: Double
    public var heightPoints: Double
    public var scale: Double
    public var maxFramesPerSecond: Int
    public init(widthPoints: Double, heightPoints: Double, scale: Double, maxFramesPerSecond: Int) {
        self.widthPoints = widthPoints; self.heightPoints = heightPoints; self.scale = scale; self.maxFramesPerSecond = maxFramesPerSecond
    }
}

/// The source of raw readings. `LiveSystemSource` reads the phone; `FixedSystemSource` returns injected values.
public protocol SystemSource: Sendable {
    func thermal() async -> ThermalLevel
    func battery() async -> BatteryRaw
    func storage() async -> StorageRaw
    func memory() async -> MemoryRaw
    func software() async -> SoftwareRaw
    func network() async -> NetworkRaw
    func display() async -> DisplayRaw?
}

/// Injected values, for tests, previews and the simulator's "inject state" debug menu.
public struct FixedSystemSource: SystemSource, Codable, Hashable {
    public var thermalLevel: ThermalLevel
    public var batteryRaw: BatteryRaw
    public var storageRaw: StorageRaw
    public var memoryRaw: MemoryRaw
    public var softwareRaw: SoftwareRaw
    public var networkRaw: NetworkRaw
    public var displayRaw: DisplayRaw?
    /// Artificial delay per probe, so the scan can be watched with injected values. Zero in tests.
    public var delayPerProbe: Double

    public init(thermalLevel: ThermalLevel, batteryRaw: BatteryRaw, storageRaw: StorageRaw, memoryRaw: MemoryRaw,
                softwareRaw: SoftwareRaw, networkRaw: NetworkRaw, displayRaw: DisplayRaw?, delayPerProbe: Double = 0) {
        self.thermalLevel = thermalLevel; self.batteryRaw = batteryRaw; self.storageRaw = storageRaw; self.memoryRaw = memoryRaw
        self.softwareRaw = softwareRaw; self.networkRaw = networkRaw; self.displayRaw = displayRaw; self.delayPerProbe = delayPerProbe
    }

    private func pause() async {
        if delayPerProbe > 0 { try? await Task.sleep(for: .seconds(delayPerProbe)) }
    }

    public func thermal() async -> ThermalLevel { await pause(); return thermalLevel }
    public func battery() async -> BatteryRaw { await pause(); return batteryRaw }
    public func storage() async -> StorageRaw { await pause(); return storageRaw }
    public func memory() async -> MemoryRaw { await pause(); return memoryRaw }
    public func software() async -> SoftwareRaw { await pause(); return softwareRaw }
    public func network() async -> NetworkRaw { await pause(); return networkRaw }
    public func display() async -> DisplayRaw? { displayRaw }

    /// A healthy phone, used as the base for tests and for the simulator's injection presets.
    public static let healthy = FixedSystemSource(
        thermalLevel: .nominal,
        batteryRaw: BatteryRaw(level: 0.82, state: .unplugged, lowPowerMode: false),
        storageRaw: StorageRaw(total: 256_000_000_000, free: 120_000_000_000, freeForImportant: 140_000_000_000, freeForOpportunistic: 118_000_000_000),
        memoryRaw: MemoryRaw(physical: 12 * 1_073_741_824, appFootprint: 40_000_000, appAvailable: 3_000_000_000, processorCount: 6,
                             activeProcessorCount: 6, warningsSeen: 0, warningsSince: nil),
        softwareRaw: SoftwareRaw(modelIdentifier: "iPhone18,1", osName: "iOS", osVersion: "27.2", osBuild: nil, uptime: 3 * 86_400,
                                 bootTime: nil, isSimulator: false, appDataBytes: 4_000_000, deviceName: "Test iPhone"),
        networkRaw: NetworkRaw(status: .satisfied, interfaces: [.wifi], isConstrained: false, isExpensive: false, supportsIPv4: true,
                               supportsIPv6: true, supportsDNS: true, vpnLikely: false, proxyConfigured: false),
        displayRaw: DisplayRaw(widthPoints: 402, heightPoints: 874, scale: 3, maxFramesPerSecond: 120)
    )
}

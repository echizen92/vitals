import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Reads the phone through public APIs only.
public struct LiveSystemSource: SystemSource {
    public init() {}

    public func thermal() async -> ThermalLevel {
        ThermalLevel(ProcessInfo.processInfo.thermalState)
    }

    public func battery() async -> BatteryRaw {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #if canImport(UIKit) && !os(watchOS)
        return await MainActor.run {
            let device = UIDevice.current
            let wasMonitoring = device.isBatteryMonitoringEnabled
            device.isBatteryMonitoringEnabled = true
            let level = device.batteryLevel
            let state: ChargeState = switch device.batteryState {
            case .unplugged: .unplugged
            case .charging: .charging
            case .full: .full
            default: .unknown
            }
            // Leave monitoring on if someone else turned it on; the app turns it on for its lifetime anyway.
            if !wasMonitoring { device.isBatteryMonitoringEnabled = wasMonitoring }
            return BatteryRaw(level: level < 0 ? nil : Double(level), state: state, lowPowerMode: lowPower)
        }
        #else
        return BatteryRaw(level: nil, state: .unknown, lowPowerMode: lowPower)
        #endif
    }

    public func storage() async -> StorageRaw {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityForOpportunisticUsageKey]
        let v = try? home.resourceValues(forKeys: keys)
        return StorageRaw(
            total: v?.volumeTotalCapacity.map(Int64.init),
            free: v?.volumeAvailableCapacity.map(Int64.init),
            freeForImportant: v?.volumeAvailableCapacityForImportantUsage,
            freeForOpportunistic: v?.volumeAvailableCapacityForOpportunisticUsage
        )
    }

    public func memory() async -> MemoryRaw {
        let info = ProcessInfo.processInfo
        var available: UInt64?
        #if os(iOS)
        available = UInt64(os_proc_available_memory())
        if available == 0 { available = nil }
        #endif
        return MemoryRaw(
            physical: info.physicalMemory,
            appFootprint: Self.footprint(),
            appAvailable: available,
            processorCount: info.processorCount,
            activeProcessorCount: info.activeProcessorCount,
            warningsSeen: MemoryWarningCounter.count,
            warningsSince: MemoryWarningCounter.since
        )
    }

    public func software() async -> SoftwareRaw {
        let info = ProcessInfo.processInfo
        let env = info.environment
        let isSim = env["SIMULATOR_MODEL_IDENTIFIER"] != nil
        let model = env["SIMULATOR_MODEL_IDENTIFIER"] ?? Self.sysctlString("hw.machine") ?? "unknown"
        var osName = "iOS"
        var deviceName: String?
        #if canImport(UIKit) && !os(watchOS)
        (osName, deviceName) = await MainActor.run { (UIDevice.current.systemName, UIDevice.current.name) }
        #else
        osName = "macOS"
        deviceName = Host.current().localizedName
        #endif
        let v = info.operatingSystemVersion
        let version = v.patchVersion > 0 ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" : "\(v.majorVersion).\(v.minorVersion)"
        return SoftwareRaw(
            modelIdentifier: model,
            osName: osName,
            osVersion: version,
            osBuild: Self.sysctlString("kern.osversion"),
            uptime: info.systemUptime,
            bootTime: Self.bootTime(),
            isSimulator: isSim,
            appDataBytes: Self.appDataBytes(),
            deviceName: deviceName
        )
    }

    public func network() async -> NetworkRaw {
        let path = await Self.currentPath()
        var interfaces: [Interface] = []
        if let path {
            if path.usesInterfaceType(.wifi) { interfaces.append(.wifi) }
            if path.usesInterfaceType(.cellular) { interfaces.append(.cellular) }
            if path.usesInterfaceType(.wiredEthernet) { interfaces.append(.wired) }
            if path.usesInterfaceType(.other) { interfaces.append(.other) }
            if path.usesInterfaceType(.loopback) { interfaces.append(.loopback) }
        }
        let status: NetworkRaw.PathStatus = switch path?.status {
        case .satisfied: .satisfied
        case .unsatisfied: .unsatisfied
        case .requiresConnection: .requiresConnection
        default: .unknown
        }
        let tunnelUp = Self.tunnelInterfaceUp()
        return NetworkRaw(
            status: status,
            interfaces: interfaces,
            isConstrained: path?.isConstrained ?? false,
            isExpensive: path?.isExpensive ?? false,
            supportsIPv4: path?.supportsIPv4 ?? false,
            supportsIPv6: path?.supportsIPv6 ?? false,
            supportsDNS: path?.supportsDNS ?? false,
            vpnLikely: tunnelUp || interfaces.contains(.other),
            proxyConfigured: Self.proxyConfigured()
        )
    }

    public func display() async -> DisplayRaw? {
        #if canImport(UIKit) && !os(watchOS)
        return await MainActor.run {
            // Read from the active window scene, never UIScreen.main (deprecated and wrong on iPhone Duo).
            let scenes = UIApplication.sharedIfAvailable?.connectedScenes.compactMap { $0 as? UIWindowScene } ?? []
            guard let screen = scenes.first(where: { $0.activationState == .foregroundActive })?.screen ?? scenes.first?.screen else { return nil }
            return DisplayRaw(widthPoints: screen.bounds.width, heightPoints: screen.bounds.height, scale: screen.scale,
                              maxFramesPerSecond: screen.maximumFramesPerSecond)
        }
        #else
        return nil
        #endif
    }

    // MARK: Helpers (all public APIs)

    static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    static func appDataBytes() -> Int64? {
        var urls = [URL(fileURLWithPath: NSHomeDirectory())]
        if SharedContainer.isUsingGroup { urls.append(SharedContainer.url) }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        for root in urls {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { continue }
            for case let url as URL in e {
                let v = try? url.resourceValues(forKeys: Set(keys))
                if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0) }
            }
        }
        return total
    }

    static func currentPath() async -> NWPath? {
        await withCheckedContinuation { (cont: CheckedContinuation<NWPath?, Never>) in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "vitals.path")
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                if once.take() {
                    monitor.cancel()
                    cont.resume(returning: path)
                }
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) {
                if once.take() {
                    monitor.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// A `utun`, `ipsec` or `ppp` interface that is up and has an address usually means a VPN.
    /// iOS keeps a few `utun` interfaces for its own services, so only interfaces carrying an
    /// IPv4 address or a non-link-local IPv6 address count.
    static func tunnelInterfaceUp() -> Bool {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return false }
        defer { freeifaddrs(ifaddr) }
        var found = false
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            let up = (p.pointee.ifa_flags & UInt32(IFF_UP)) != 0
            if up, ["utun", "ipsec", "ppp"].contains(where: { name.hasPrefix($0) }), let addr = p.pointee.ifa_addr {
                let family = addr.pointee.sa_family
                if family == UInt8(AF_INET) {
                    found = true
                } else if family == UInt8(AF_INET6) {
                    let isLinkLocal = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        $0.pointee.sin6_addr.__u6_addr.__u6_addr8.0 == 0xfe && ($0.pointee.sin6_addr.__u6_addr.__u6_addr8.1 & 0xc0) == 0x80
                    }
                    if !isLinkLocal { found = true }
                }
            }
            ptr = p.pointee.ifa_next
        }
        return found
    }

    static func proxyConfigured() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return false }
        let http = (settings[kCFNetworkProxiesHTTPEnable as String] as? Int) == 1
        let pac = (settings[kCFNetworkProxiesProxyAutoConfigEnable as String] as? Int) == 1
        return http || pac
    }
}

/// A thread-safe "first caller wins" flag.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

#if canImport(UIKit) && !os(watchOS)
extension UIApplication {
    /// `UIApplication.shared` is unavailable in app extensions; widgets and the share extension get nil.
    @MainActor static var sharedIfAvailable: UIApplication? {
        let selector = NSSelectorFromString("sharedApplication")
        guard UIApplication.responds(to: selector) else { return nil }
        return UIApplication.perform(selector)?.takeUnretainedValue() as? UIApplication
    }
}
#endif

/// The model identifier, read synchronously (for layout decisions such as drawing a Duo).
public enum DeviceIdentity {
    public static let modelIdentifier: String = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        ?? LiveSystemSource.sysctlString("hw.machine") ?? "unknown"
    public static var isDuo: Bool { Catalog.isDuo(modelIdentifier) }
    public static var modelName: String { Catalog.modelName(for: modelIdentifier) ?? modelIdentifier }
}

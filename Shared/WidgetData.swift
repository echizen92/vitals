import Foundation
import VitalsKit

/// Everything a widget shows, gathered in one place. Built by the widget extension on each timeline
/// reload, and by the app's widget gallery (debug) from the same code.
///
/// UNVERIFIED (plan §4): whether a widget extension can read `UIDevice.batteryLevel` (it may return -1)
/// and whether `ProcessInfo.thermalState` in the extension reflects the phone. Both are read here, shown only
/// when present, and every widget says when it last updated. Needs the device (Docs/needs-device.md).
struct WidgetData: Sendable {
    var date: Date
    var thermal: ThermalLevel
    var batteryLevel: Double?
    var charge: ChargeState
    var lowPower: Bool
    var drainPerHour: Double?
    var storageTotal: Int64?
    var storageFree: Int64?
    var snapshot: WidgetSnapshot?
    var samples24h: [Sample]
    /// True when values are synthetic (previews, placeholder, gallery with injected values).
    var isPlaceholder: Bool

    static func load(now: Date = .now, takeSample: Bool) async -> WidgetData {
        let source = LiveSystemSource()
        let battery = await source.battery()
        let thermal = await source.thermal()
        let storage = await source.storage()
        let store = try? VitalsStore()
        if takeSample, let store {
            // "Each timeline reload also appends a sample", deduplicated across the four widgets.
            let s = Sample(takenAt: now, thermal: thermal, batteryLevel: battery.level, charge: battery.state, lowPowerMode: battery.lowPowerMode, source: .widget)
            _ = try? await store.insertIfStale(s)
        }
        let samples = (try? await store?.samples(from: now.addingTimeInterval(-86_400))) ?? []
        let real = samples.filter { $0.source != .fixture }
        return WidgetData(date: now, thermal: thermal, batteryLevel: battery.level, charge: battery.state, lowPower: battery.lowPowerMode,
                          drainPerHour: BatteryMath.drainPerHour(real, now: now), storageTotal: storage.total,
                          storageFree: storage.freeForImportant ?? storage.free, snapshot: WidgetSnapshot.load(), samples24h: real, isPlaceholder: false)
    }

    static func placeholder(now: Date = .now) -> WidgetData {
        let samples = SyntheticSamples.day(endingAt: now, step: 30 * 60)
        return WidgetData(date: now, thermal: .fair, batteryLevel: 0.64, charge: .unplugged, lowPower: false, drainPerHour: 7,
                          storageTotal: 256_000_000_000, storageFree: 96_000_000_000,
                          snapshot: WidgetSnapshot(checkupAt: now.addingTimeInterval(-3600), areas: Area.allCases.map {
                              .init(area: $0, status: $0 == .heat ? .attention : $0 == .battery ? .unknown : .good, sentence: "")
                          }, storageTotal: nil, storageFree: nil, drainPerHour: nil, writtenAt: now),
                          samples24h: samples, isPlaceholder: true)
    }
}

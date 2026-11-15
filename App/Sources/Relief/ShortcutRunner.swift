import UIKit
import VitalsKit

/// "One tap through Shortcuts" (plan §5.14a). Shortcuts can do what an app cannot (Low Power Mode, brightness,
/// radios, charge limit, restart prompt). Vitals runs its own signed shortcuts with the public
/// `shortcuts://run-shortcut` URL and gets control back through `x-success`, so it can measure before and after.
/// Shortcut source is in shortcuts/ (unqforge, Python); the signed files are built on a Mac and bundled.
/// UNVERIFIED (needs the Duo): first-run prompts, whether a bundled file can be handed straight to Shortcuts,
/// and behaviour on iOS 27.2.
enum ReliefShortcut: String, CaseIterable, Identifiable {
    case coolDown = "Vitals Cool down"
    case saveBattery = "Vitals Save battery"
    case restart = "Vitals Restart"
    /// Not bundled: no device-seen evidence of the charge-limit action's value parameter (shortcuts/README.md).
    case protectBattery = "Vitals Protect battery"

    var id: String { rawValue }
    var actionID: String {
        switch self {
        case .coolDown: "relief.coolDown"
        case .saveBattery: "relief.saveBattery"
        case .restart: "relief.restart"
        case .protectBattery: "relief.protectBattery"
        }
    }
    var undo: String? { self == .restart ? nil : "Vitals Undo \(rawValue.dropFirst("Vitals ".count))" }
    var fileStem: String { rawValue.replacingOccurrences(of: " ", with: "-") }
    var symbol: String {
        switch self {
        case .coolDown: "snowflake"
        case .saveBattery: "battery.75percent"
        case .restart: "restart"
        case .protectBattery: "battery.100percent.bolt"
        }
    }

    /// The signed shortcut bundled with the app, if this build has it.
    var bundledFile: URL? { Bundle.main.url(forResource: fileStem, withExtension: "shortcut", subdirectory: "Shortcuts") }

    static var anyBundled: Bool { allCases.contains { $0.bundledFile != nil } }

    /// Every signed file in the bundle, Undo shortcuts included.
    static var allBundledFiles: [URL] {
        (Bundle.main.urls(forResourcesWithExtension: "shortcut", subdirectory: "Shortcuts") ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func runURL(_ name: String, actionID: String) -> URL? {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: "vitals://relief-done?action=\(actionID)"),
            URLQueryItem(name: "x-cancel", value: "vitals://relief-cancel?action=\(actionID)"),
            URLQueryItem(name: "x-error", value: "vitals://relief-error?action=\(actionID)"),
        ]
        return c.url
    }

    @MainActor
    static func canOpenShortcuts() -> Bool {
        UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!)
    }
}

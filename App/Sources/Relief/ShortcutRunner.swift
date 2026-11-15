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
    /// Undo runs the same shortcut with the text "undo" as its input (shortcuts/src). Restart has nothing to undo.
    var hasUndo: Bool { self != .restart }
    /// The row's short title, as shown in Relief ("Cool down").
    var title: String { String(rawValue.dropFirst("Vitals ".count)) }
    var symbol: String {
        switch self {
        case .coolDown: "snowflake"
        case .saveBattery: "battery.75percent"
        case .restart: "restart"
        case .protectBattery: "battery.100percent.bolt"
        }
    }

    /// The signed shortcut bundled with the app, if this build has it. Shortcuts names an imported shortcut after
    /// its file, so the file is named exactly `rawValue` (spaces included) and Run asks for that same name.
    var bundledFile: URL? { Bundle.main.url(forResource: rawValue, withExtension: "shortcut", subdirectory: "Shortcuts") }

    static var anyBundled: Bool { allCases.contains { $0.bundledFile != nil } }

    /// The callback action for Undo, e.g. "undo.relief.coolDown", so an error can name the row.
    var undoActionID: String { "undo." + actionID }

    static func forCallback(_ actionID: String) -> ReliefShortcut? {
        let id = actionID.hasPrefix("undo.") ? String(actionID.dropFirst("undo.".count)) : actionID
        return allCases.first { $0.actionID == id }
    }

    func runURL(undo: Bool) -> URL? {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        let actionID = undo ? undoActionID : self.actionID
        c.queryItems = [
            URLQueryItem(name: "name", value: rawValue),
        ]
        if undo {
            c.queryItems! += [URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: "undo")]
        }
        c.queryItems! += [
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

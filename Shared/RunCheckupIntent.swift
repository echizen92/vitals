import AppIntents
import VitalsKit

/// "Run check-up": the Control Center / Lock Screen control and a Shortcuts action. Opens Vitals and starts
/// the scan. Compiled into both the app and the widget extension, as iOS requires for intents that open the app.
struct RunCheckupIntent: AppIntent {
    static let title: LocalizedStringResource = "Run check-up"
    static let description = IntentDescription("Opens Vitals and checks battery, heat, storage, memory, network and software.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app reads this flag when it becomes active and starts the scan.
        SharedContainer.defaults.set(Date.now, forKey: PendingAction.scanKey)
        return .result()
    }
}

enum PendingAction {
    static let scanKey = "pending.scan"

    /// True once if a scan was requested in the last two minutes.
    static func takeScanRequest(now: Date = .now) -> Bool {
        let d = SharedContainer.defaults
        guard let at = d.object(forKey: scanKey) as? Date else { return false }
        d.removeObject(forKey: scanKey)
        return now.timeIntervalSince(at) < 120
    }
}

struct VitalsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunCheckupIntent(), phrases: ["Run a check-up in \(.applicationName)", "Check my phone with \(.applicationName)"],
                    shortTitle: "Run check-up", systemImageName: "waveform.path.ecg")
    }
}

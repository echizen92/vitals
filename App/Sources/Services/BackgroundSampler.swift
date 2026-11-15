import BackgroundTasks
import UserNotifications
import WidgetKit
import VitalsKit

/// Takes a timeline sample when iOS grants background refresh time. iOS decides when (and whether)
/// this runs; there is no continuous background monitoring on iOS, so gaps in the timeline are normal.
enum BackgroundSampler {
    static let identifier = "sg.com.vitals.app.sample"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { return }
            schedule()
            // BGTask is not Sendable; it is only touched again to complete or expire, which iOS allows from any thread.
            nonisolated(unsafe) let task = refresh
            let work = Task {
                let sample = await CheckupRunner(source: LiveSystemSource()).sample(source: .background)
                if let store = try? VitalsStore() {
                    try? await store.insert(sample)
                }
                await HeatAlerts.shared.consider(sample)
                WidgetCenter.shared.reloadAllTimelines()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Optional local notification when a sample sees serious or critical heat. It can only fire when
/// Vitals has runtime (open, background refresh, widget reload), so it can be late; the settings
/// screen says so.
actor HeatAlerts {
    static let shared = HeatAlerts()
    static let enabledKey = "alerts.heat.enabled"
    private let lastKey = "alerts.heat.last"

    static var isEnabled: Bool { SharedContainer.defaults.bool(forKey: enabledKey) }

    static func setEnabled(_ on: Bool) async -> Bool {
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            SharedContainer.defaults.set(granted, forKey: enabledKey)
            return granted
        }
        SharedContainer.defaults.set(false, forKey: enabledKey)
        return false
    }

    func consider(_ sample: Sample, now: Date = .now) async {
        guard Self.isEnabled, sample.thermal.isHot else { return }
        let d = SharedContainer.defaults
        if let last = d.object(forKey: lastKey) as? Date, now.timeIntervalSince(last) < 3600 { return }
        d.set(now, forKey: lastKey)
        let content = UNMutableNotificationContent()
        content.title = sample.thermal == .critical ? "Your phone is very hot" : "Your phone is running hot"
        content.body = "Seen at \(sample.takenAt.formatted(date: .omitted, time: .shortened))\(sample.charge.isPluggedIn ? " while charging" : ""). Open Vitals to see what was going on."
        content.userInfo = ["url": "vitals://heat"]
        let request = UNNotificationRequest(identifier: "heat-\(Int(now.timeIntervalSince1970))", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

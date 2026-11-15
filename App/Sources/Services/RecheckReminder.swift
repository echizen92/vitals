import Foundation
import UserNotifications
import VitalsKit

/// "Re-check tomorrow" is the main advice in an expected-and-temporary case (plan §4a item 8). After the next
/// 08:00 analytics file exists, a local notification asks for it so Vitals can compare the two days.
/// Only scheduled if notifications are already allowed (heat alerts on); Vitals does not ask just for this.
enum RecheckReminder {
    static let id = "vitals.recheck"

    static func schedule(for result: CaseResult) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let primary = result.primary, let when = primary.recheckAfter, when > .now else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time to check again"
        content.body = "Today's analytics file is ready. Share it with Vitals to see whether \(primary.title.lowercased()) has eased."
        content.userInfo = ["url": "vitals://logs"]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

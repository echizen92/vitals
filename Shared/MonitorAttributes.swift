import Foundation
import VitalsKit
#if canImport(ActivityKit)
import ActivityKit

/// "Watch my phone while I do X": a user-started monitoring session on the Lock Screen and in the
/// Dynamic Island. Updated locally by the app while it has runtime (no push server), so updates pause
/// when iOS suspends Vitals; the activity says when it last updated.
struct MonitorAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var thermal: ThermalLevel
        var batteryLevel: Double?
        var drainPerHour: Double?
        var updatedAt: Date
        var peak: ThermalLevel
        /// Set on the final update.
        var summary: String?
    }

    var purpose: String
    var startedAt: Date
}
#endif

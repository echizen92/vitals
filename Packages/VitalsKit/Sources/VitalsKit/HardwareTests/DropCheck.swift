import Foundation

/// "I dropped my phone": one run through every hardware test, in the order a drop most often damages things
/// (screen and touch first, then cameras, sound, buttons, sensors, radios). The app runs the check-up first
/// (battery, heat, storage), then walks this plan; each step can be skipped. The summary only uses results
/// from this run, so an old pass never hides new damage.
public enum DropCheck {
    /// Every test, most drop-prone first. Duo-only tests sit next to the display ones.
    public static let order: [HardwareTestKind] = [
        .display, .touch, .duoDisplays, .hinge, .cameras, .flashlight,
        .speakers, .microphones, .buttons, .haptics, .faceID, .proximity, .motion,
        .wifiCellular, .bluetooth, .gps, .nfc,
    ]

    public static func plan(isDuo: Bool) -> [HardwareTestKind] { order.filter { isDuo || !$0.duoOnly } }

    public struct Summary: Sendable, Hashable {
        public var failed: [HardwareTestKind] = []
        public var passed: [HardwareTestKind] = []
        /// Skipped or not available on this phone.
        public var notChecked: [HardwareTestKind] = []

        public var verdict: Verdict {
            if !failed.isEmpty { return .damageFound }
            if passed.isEmpty { return .notChecked }
            return notChecked.isEmpty ? .allPassed : .passedWithGaps
        }
    }

    public enum Verdict: Sendable, Hashable { case damageFound, allPassed, passedWithGaps, notChecked }

    /// Results recorded at or after `since`, read against `plan`, in plan order.
    public static func summarize(plan: [HardwareTestKind], results: [HardwareTestResult], since: Date) -> Summary {
        var s = Summary()
        for k in plan {
            guard let r = results.first(where: { $0.kind == k }), r.testedAt >= since else { s.notChecked.append(k); continue }
            switch r.outcome {
            case .passed: s.passed.append(k)
            case .failed: s.failed.append(k)
            case .skipped, .unavailable: s.notChecked.append(k)
            }
        }
        return s
    }
}

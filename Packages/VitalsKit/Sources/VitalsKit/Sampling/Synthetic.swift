import Foundation

/// Synthetic timelines for tests and the Simulator. Marked `.fixture` so they never mix with real samples
/// and can be deleted on their own.
public enum SyntheticSamples {
    /// A day of samples every `step` seconds: cool overnight, a charging warm-up in the morning,
    /// one unplugged hot spell in the afternoon, and a cool evening.
    public static func day(endingAt end: Date = .now, step: TimeInterval = 15 * 60) -> [Sample] {
        var out: [Sample] = []
        let start = end.addingTimeInterval(-86_400)
        var level = 0.55
        var t = start
        while t <= end {
            let h = t.timeIntervalSince(start) / 3600
            var thermal: ThermalLevel = .nominal
            var charge: ChargeState = .unplugged
            switch h {
            case 6..<8: charge = .charging; thermal = h < 7 ? .fair : .nominal; level = min(1, level + 0.1)
            case 8..<9: charge = .full; level = 1
            case 14..<15.25: thermal = h < 14.5 ? .serious : (h < 15 ? .critical : .serious); level -= 0.07
            case 15.25..<16: thermal = .fair; level -= 0.03
            case 20..<20.6: thermal = .serious; level -= 0.04
            default: level -= 0.012
            }
            level = max(0.05, level)
            out.append(Sample(takenAt: t, thermal: thermal, batteryLevel: level, charge: charge, lowPowerMode: false, source: .fixture))
            t = t.addingTimeInterval(step)
        }
        return out
    }
}

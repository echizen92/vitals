import Foundation

/// Battery drain and charge rates worked out from samples. Always `inferred`.
public enum BatteryMath {
    /// Percent per hour while on battery (positive = draining), over samples within `window` of `now`.
    /// Only spans of consecutive on-battery samples at least `minSpan` long count, so a pair of
    /// samples a minute apart cannot produce a wild number.
    public static func drainPerHour(_ samples: [Sample], now: Date = .now, window: TimeInterval = 6 * 3600,
                                    minSpan: TimeInterval = 15 * 60) -> Double? {
        rate(samples, now: now, window: window, minSpan: minSpan) { $0 == .unplugged }.map { -$0 }
    }

    /// Percent per hour while charging (positive = gaining).
    public static func chargePerHour(_ samples: [Sample], now: Date = .now, window: TimeInterval = 6 * 3600,
                                     minSpan: TimeInterval = 10 * 60) -> Double? {
        rate(samples, now: now, window: window, minSpan: minSpan) { $0 == .charging }
    }

    /// Signed rate (percent per hour) over runs of samples whose charge state matches.
    static func rate(_ samples: [Sample], now: Date, window: TimeInterval, minSpan: TimeInterval,
                     matching: (ChargeState) -> Bool) -> Double? {
        let recent = samples
            .filter { $0.takenAt >= now.addingTimeInterval(-window) && $0.takenAt <= now && $0.batteryLevel != nil }
            .sorted { $0.takenAt < $1.takenAt }
        var totalChange = 0.0, totalTime = 0.0
        var run: [Sample] = []
        func closeRun() {
            if let a = run.first, let b = run.last, let la = a.batteryLevel, let lb = b.batteryLevel {
                let span = b.takenAt.timeIntervalSince(a.takenAt)
                if span >= minSpan {
                    totalChange += (lb - la) * 100
                    totalTime += span
                }
            }
            run = []
        }
        for s in recent {
            if matching(s.charge) {
                // A gap over 90 minutes breaks the run: we do not know what happened in between.
                if let last = run.last, s.takenAt.timeIntervalSince(last.takenAt) > 90 * 60 { closeRun() }
                run.append(s)
            } else {
                closeRun()
            }
        }
        closeRun()
        guard totalTime > 0 else { return nil }
        return totalChange / (totalTime / 3600)
    }
}

public enum HotSpellDetector {
    /// Groups consecutive serious/critical samples into spells. A non-hot sample, or a gap longer
    /// than `maxGap` with no samples at all, ends a spell: Vitals cannot see what happened in a gap.
    public static func detect(_ samples: [Sample], maxGap: TimeInterval = 45 * 60) -> [HotSpell] {
        let sorted = samples.filter(\.hasThermal).sorted { $0.takenAt < $1.takenAt }
        guard let latest = sorted.last else { return [] }
        var spells: [HotSpell] = []
        var current: [Sample] = []

        func close() {
            guard let first = current.first, let last = current.last else { return }
            let peak = current.map(\.thermal).max() ?? .serious
            let charging = current.contains { $0.charge.isPluggedIn }
            var drain: Double?
            if !charging {
                let levels = current.compactMap { s in s.batteryLevel.map { (s.takenAt, $0) } }
                if let a = levels.first, let b = levels.last, b.0.timeIntervalSince(a.0) >= 5 * 60 {
                    drain = (a.1 - b.1) * 100 / (b.0.timeIntervalSince(a.0) / 3600)
                }
            }
            spells.append(HotSpell(start: first.takenAt, end: last.takenAt, peak: peak, drainPerHour: drain,
                                   wasCharging: charging, sampleCount: current.count, ongoing: last.takenAt == latest.takenAt))
            current = []
        }

        for s in sorted {
            if s.thermal.isHot {
                if let last = current.last, s.takenAt.timeIntervalSince(last.takenAt) > maxGap { close() }
                current.append(s)
            } else {
                close()
            }
        }
        close()
        return spells
    }
}

/// How well the timeline covers a period. Shown next to the timeline so gaps are never hidden.
public struct Coverage: Sendable, Hashable {
    public var sampleCount: Int
    /// Fraction of the period within `bucket` of at least one sample.
    public var fraction: Double

    public static func of(_ samples: [Sample], from start: Date, to end: Date, bucket: TimeInterval = 3600) -> Coverage {
        let inRange = samples.filter { $0.takenAt >= start && $0.takenAt <= end }
        let total = max(1, Int((end.timeIntervalSince(start) / bucket).rounded(.up)))
        var hit = Set<Int>()
        for s in inRange { hit.insert(Int(s.takenAt.timeIntervalSince(start) / bucket)) }
        return Coverage(sampleCount: inRange.count, fraction: Double(hit.count) / Double(total))
    }
}

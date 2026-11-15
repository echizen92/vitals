import Foundation

/// A finished "watch my phone" session, saved to the heat timeline.
public struct MonitorSessionRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: Date { start }
    public var purpose: String
    public var start: Date
    public var end: Date
    public var peak: ThermalLevel
    public var drainPerHour: Double?
    public var sampleCount: Int
    public var hotMinutes: Double

    public init(purpose: String, start: Date, end: Date, peak: ThermalLevel, drainPerHour: Double?, sampleCount: Int, hotMinutes: Double) {
        self.purpose = purpose; self.start = start; self.end = end; self.peak = peak; self.drainPerHour = drainPerHour
        self.sampleCount = sampleCount; self.hotMinutes = hotMinutes
    }

    /// Builds the summary from the samples taken during the session.
    public static func summarize(purpose: String, start: Date, end: Date, samples: [Sample]) -> MonitorSessionRecord {
        let inside = samples.filter { $0.takenAt >= start && $0.takenAt <= end }.sorted { $0.takenAt < $1.takenAt }
        let peak = inside.map(\.thermal).max() ?? .nominal
        let spells = HotSpellDetector.detect(inside)
        let hot = spells.reduce(0) { $0 + $1.duration } / 60
        let drain = BatteryMath.drainPerHour(inside, now: end, window: end.timeIntervalSince(start) + 60, minSpan: 5 * 60)
        return MonitorSessionRecord(purpose: purpose, start: start, end: end, peak: peak, drainPerHour: drain, sampleCount: inside.count, hotMinutes: hot)
    }

    public var summaryLine: String {
        var parts = ["\(DurationFormatting.string(seconds: max(60, end.timeIntervalSince(start))))", "peak \(peak.label.lowercased())"]
        if hotMinutes >= 1 { parts.append("hot for \(Int(hotMinutes)) min") }
        if let d = drainPerHour { parts.append("draining \(Int(d.rounded()))%/h") }
        return parts.joined(separator: ", ")
    }
}

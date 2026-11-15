import Foundation

/// One benchmark run. Scores are work per second for a fixed workload; higher is better.
public struct BenchmarkResult: Codable, Sendable, Hashable {
    public enum Verdict: String, Codable, Sendable { case belowRange, inRange, aboveRange }

    public struct Score: Codable, Sendable, Hashable, Identifiable {
        public var id: String          // cpuSingle, cpuMulti, gpu, storageWrite, storageRead
        public var label: String
        public var value: Double
        public var unit: String
        public var seconds: Double
        /// Expected range for this model, if the bundled table has it.
        public var expected: ClosedRange<Double>?
        public init(id: String, label: String, value: Double, unit: String, seconds: Double, expected: ClosedRange<Double>?) {
            self.id = id; self.label = label; self.value = value; self.unit = unit; self.seconds = seconds; self.expected = expected
        }
        public var verdict: Verdict? {
            guard let e = expected else { return nil }
            return value < e.lowerBound ? .belowRange : value > e.upperBound ? .aboveRange : .inRange
        }
    }

    public var takenAt: Date
    public var modelIdentifier: String
    public var thermalAtStart: ThermalLevel
    public var thermalAtEnd: ThermalLevel
    public var lowPowerMode: Bool
    public var scores: [Score]
    public var totalSeconds: Double
    /// False when the bundled table has no entry for this model: show raw results only.
    public var hasBaseline: Bool

    public init(takenAt: Date, modelIdentifier: String, thermalAtStart: ThermalLevel, thermalAtEnd: ThermalLevel, lowPowerMode: Bool,
                scores: [Score], totalSeconds: Double, hasBaseline: Bool) {
        self.takenAt = takenAt; self.modelIdentifier = modelIdentifier; self.thermalAtStart = thermalAtStart; self.thermalAtEnd = thermalAtEnd
        self.lowPowerMode = lowPowerMode; self.scores = scores; self.totalSeconds = totalSeconds; self.hasBaseline = hasBaseline
    }

    /// Worst verdict across scores that have a baseline.
    public var verdict: Verdict? {
        let v = scores.compactMap(\.verdict)
        if v.isEmpty { return nil }
        if v.contains(.belowRange) { return .belowRange }
        return v.allSatisfy { $0 == .aboveRange } ? .aboveRange : .inRange
    }

    public var summaryLine: String {
        scores.map { "\($0.label) \($0.value.formatted(.number.precision(.fractionLength(0...1)))) \($0.unit)" }.joined(separator: ", ")
    }
}

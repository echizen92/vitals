import Foundation

/// Mirrors `ProcessInfo.ThermalState`. iOS gives only these four levels; there are no degrees on-device.
public enum ThermalLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case nominal = 0, fair = 1, serious = 2, critical = 3

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }

    public var label: String {
        switch self {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        }
    }

    /// Four characters or fewer, for circular complications.
    public var shortLabel: String {
        switch self {
        case .nominal: "OK"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Crit"
        }
    }

    /// What iOS itself says each level means, in plain words.
    public var meaning: String {
        switch self {
        case .nominal: "Within normal limits."
        case .fair: "iOS may start trimming background work."
        case .serious: "iOS is slowing the phone down to cool it."
        case .critical: "iOS is cutting performance hard and may pause charging."
        }
    }

    public var isHot: Bool { self >= .serious }
    public static func < (l: ThermalLevel, r: ThermalLevel) -> Bool { l.rawValue < r.rawValue }
}

public enum ChargeState: String, Codable, Sendable, CaseIterable {
    case unknown, unplugged, charging, full

    public var label: String {
        switch self {
        case .unknown: "Unknown"
        case .unplugged: "On battery"
        case .charging: "Charging"
        case .full: "Full"
        }
    }

    public var isPluggedIn: Bool { self == .charging || self == .full }
}

/// Who took a sample. Samples only exist while something of ours has runtime.
public enum SampleSource: String, Codable, Sendable, CaseIterable {
    case app, background, widget, liveActivity, companion, fixture
}

/// One point on the heat timeline.
public struct Sample: Codable, Sendable, Hashable {
    public var takenAt: Date
    public var thermal: ThermalLevel
    /// 0...1, nil when iOS reports -1 (simulator, or monitoring off).
    public var batteryLevel: Double?
    public var charge: ChargeState
    public var lowPowerMode: Bool
    public var source: SampleSource
    /// Battery temperature in °C. Only ever set by a Mac companion capture; never on-device.
    public var temperatureC: Double?
    /// True when the sample came without an iOS thermal state (Mac companion captures). Such samples carry
    /// temperature only; `thermal` is a placeholder and every heat view and detector skips them.
    public var thermalUnknown: Bool

    public init(takenAt: Date, thermal: ThermalLevel, batteryLevel: Double?, charge: ChargeState,
                lowPowerMode: Bool, source: SampleSource, temperatureC: Double? = nil, thermalUnknown: Bool = false) {
        self.takenAt = takenAt; self.thermal = thermal; self.batteryLevel = batteryLevel; self.charge = charge
        self.lowPowerMode = lowPowerMode; self.source = source; self.temperatureC = temperatureC; self.thermalUnknown = thermalUnknown
    }

    public var hasThermal: Bool { !thermalUnknown }

    enum CodingKeys: String, CodingKey { case takenAt, thermal, batteryLevel, charge, lowPowerMode, source, temperatureC, thermalUnknown }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        takenAt = try c.decode(Date.self, forKey: .takenAt)
        let t = try c.decodeIfPresent(ThermalLevel.self, forKey: .thermal)
        thermal = t ?? .nominal
        thermalUnknown = try c.decodeIfPresent(Bool.self, forKey: .thermalUnknown) ?? (t == nil)
        batteryLevel = try c.decodeIfPresent(Double.self, forKey: .batteryLevel)
        charge = try c.decodeIfPresent(ChargeState.self, forKey: .charge) ?? .unknown
        // Companion captures cannot see Low Power Mode; it is not shown for them.
        lowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .lowPowerMode) ?? false
        source = try c.decodeIfPresent(SampleSource.self, forKey: .source) ?? .companion
        temperatureC = try c.decodeIfPresent(Double.self, forKey: .temperatureC)
    }
}

/// A run of samples at serious or critical thermal state.
public struct HotSpell: Codable, Sendable, Hashable, Identifiable {
    public var start: Date
    public var end: Date
    public var peak: ThermalLevel
    /// Battery percent per hour, positive means draining. Nil when there were not enough battery readings.
    public var drainPerHour: Double?
    public var wasCharging: Bool
    public var sampleCount: Int
    /// True when the spell's last sample is the latest sample, i.e. it may still be going on.
    public var ongoing: Bool

    public var id: Date { start }
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(start: Date, end: Date, peak: ThermalLevel, drainPerHour: Double?, wasCharging: Bool, sampleCount: Int, ongoing: Bool) {
        self.start = start; self.end = end; self.peak = peak; self.drainPerHour = drainPerHour
        self.wasCharging = wasCharging; self.sampleCount = sampleCount; self.ongoing = ongoing
    }
}

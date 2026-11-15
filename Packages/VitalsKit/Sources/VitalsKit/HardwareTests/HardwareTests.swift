import Foundation

/// The guided hardware tests. Definitions live here; the interactive screens live in the app.
public enum HardwareTestKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case touch, display, speakers, microphones, cameras, haptics, buttons, motion, proximity, faceID
    case bluetooth, wifiCellular, gps, nfc, flashlight, duoDisplays, hinge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .touch: "Touch screen"
        case .display: "Display"
        case .speakers: "Speakers"
        case .microphones: "Microphones"
        case .cameras: "Cameras"
        case .haptics: "Haptics"
        case .buttons: "Buttons"
        case .motion: "Motion sensors"
        case .proximity: "Proximity sensor"
        case .faceID: "Face ID"
        case .bluetooth: "Bluetooth"
        case .wifiCellular: "Wi-Fi and cellular"
        case .gps: "GPS"
        case .nfc: "NFC"
        case .flashlight: "Flashlight"
        case .duoDisplays: "Both displays"
        case .hinge: "Hinge"
        }
    }

    public var symbol: String {
        switch self {
        case .touch: "hand.draw"
        case .display: "rectangle.inset.filled"
        case .speakers: "speaker.wave.3"
        case .microphones: "mic"
        case .cameras: "camera"
        case .haptics: "iphone.radiowaves.left.and.right"
        case .buttons: "button.vertical.right.press"
        case .motion: "gyroscope"
        case .proximity: "sensor"
        case .faceID: "faceid"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .wifiCellular: "wifi"
        case .gps: "location"
        case .nfc: "wave.3.right"
        case .flashlight: "flashlight.on.fill"
        case .duoDisplays: "rectangle.split.2x1"
        case .hinge: "book"
        }
    }

    /// What the person does, in one line.
    public var instruction: String {
        switch self {
        case .touch: "Paint every square of the grid with your finger."
        case .display: "Look for dead or stuck pixels on each solid colour, then watch the brightness sweep."
        case .speakers: "Play a tone from each speaker and say whether you heard it."
        case .microphones: "Record a few seconds from each microphone and play it back."
        case .cameras: "Check each lens shows a sharp, clean picture."
        case .haptics: "Feel each pattern and say whether it played."
        case .buttons: "Press each button when asked."
        case .motion: "Move the phone and watch the live sensor values change."
        case .proximity: "Cover the top of the screen with your hand."
        case .faceID: "Look at the phone when Face ID asks."
        case .bluetooth: "Scan for nearby Bluetooth devices."
        case .wifiCellular: "Check which networks the phone can use right now."
        case .gps: "Get a location fix and see its accuracy."
        case .nfc: "Start an NFC reader session."
        case .flashlight: "Turn the flashlight on and off."
        case .duoDisplays: "Check the outer and inner displays each show the test pattern."
        case .hinge: "Open and close the phone and watch the reported hinge state."
        }
    }

    /// Tests that only make sense on iPhone Duo.
    public var duoOnly: Bool { self == .duoDisplays || self == .hinge }

    /// Pass/fail is decided by the app (e.g. a scan found devices) rather than by the person.
    public var automatic: Bool {
        switch self {
        case .bluetooth, .wifiCellular, .gps, .nfc, .faceID: true
        default: false
        }
    }

    public static func suite(isDuo: Bool) -> [HardwareTestKind] {
        allCases.filter { isDuo || !$0.duoOnly }
    }
}

public enum TestOutcome: String, Codable, Sendable, CaseIterable {
    case passed, failed, skipped, unavailable
    public var label: String {
        switch self {
        case .passed: "Passed"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .unavailable: "Not available"
        }
    }
}

public struct HardwareTestResult: Codable, Sendable, Hashable, Identifiable {
    public var kind: HardwareTestKind
    public var outcome: TestOutcome
    public var notes: String
    /// Measured details, e.g. "8 of 8 rows painted", "4 devices seen", "±5 m". Never media.
    public var details: [String]
    public var testedAt: Date
    public var id: HardwareTestKind { kind }

    public init(kind: HardwareTestKind, outcome: TestOutcome, notes: String = "", details: [String] = [], testedAt: Date = .now) {
        self.kind = kind; self.outcome = outcome; self.notes = notes; self.details = details; self.testedAt = testedAt
    }
}

/// The grid for the touch test, kept here so its completion logic is unit-tested.
public struct TouchGrid: Sendable, Hashable {
    public let columns: Int
    public let rows: Int
    public private(set) var painted: Set<Int> = []

    public init(columns: Int, rows: Int) { self.columns = columns; self.rows = rows }

    /// Paint the cell under a point in a canvas of `size`. Returns true if the cell was new.
    @discardableResult
    public mutating func paint(x: Double, y: Double, width: Double, height: Double) -> Bool {
        guard width > 0, height > 0, x >= 0, y >= 0, x < width, y < height else { return false }
        let c = min(columns - 1, Int(x / width * Double(columns)))
        let r = min(rows - 1, Int(y / height * Double(rows)))
        return painted.insert(r * columns + c).inserted
    }

    /// Paints every cell along a straight line, so a fast drag (touch events far apart) leaves no gaps.
    /// Returns how many new cells were painted.
    @discardableResult
    public mutating func paintLine(from a: (x: Double, y: Double), to b: (x: Double, y: Double), width: Double, height: Double) -> Int {
        let cell = min(width / Double(columns), height / Double(rows))
        let length = hypot(b.x - a.x, b.y - a.y)
        let steps = max(1, Int(length / (cell / 3)))
        var n = 0
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            if paint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, width: width, height: height) { n += 1 }
        }
        return n
    }

    public var total: Int { columns * rows }
    public var progress: Double { Double(painted.count) / Double(total) }
    public var complete: Bool { painted.count == total }
    public func isPainted(column: Int, row: Int) -> Bool { painted.contains(row * columns + column) }
    public var missing: [Int] { (0..<total).filter { !painted.contains($0) } }
}

/// Decides whether a live sensor is actually reporting change (not stuck, not silent).
/// Keeps a short window of values and calls the sensor "live" once the spread exceeds `threshold`.
public struct SignalActivity: Sendable, Hashable {
    public let threshold: Double
    public let window: Int
    public private(set) var values: [Double] = []
    public private(set) var everLive = false

    public init(threshold: Double, window: Int = 60) { self.threshold = threshold; self.window = window }

    public mutating func add(_ v: Double) {
        guard v.isFinite else { return }
        values.append(v)
        if values.count > window { values.removeFirst(values.count - window) }
        if spread > threshold { everLive = true }
    }

    public var spread: Double { (values.max() ?? 0) - (values.min() ?? 0) }
    public var count: Int { values.count }
}

/// One tone for the speaker test, as samples, so it is testable without audio hardware.
public enum ToneGenerator {
    /// A sine at `frequency` with 10 ms fade in/out to avoid clicks.
    public static func samples(frequency: Double, seconds: Double, sampleRate: Double = 44_100, amplitude: Double = 0.5) -> [Float] {
        let n = Int(seconds * sampleRate)
        let fade = Int(0.01 * sampleRate)
        return (0..<n).map { i in
            var a = amplitude
            if i < fade { a *= Double(i) / Double(fade) }
            if i > n - fade { a *= Double(n - i) / Double(fade) }
            return Float(a * sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
    }
}

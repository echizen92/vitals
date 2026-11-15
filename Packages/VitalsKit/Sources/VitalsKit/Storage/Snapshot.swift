import Foundation

/// The small summary the app leaves in the app group for widgets: last check-up statuses and storage.
/// Widgets add their own fresh thermal/battery reading on each reload where iOS allows it.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public struct AreaStatus: Codable, Sendable, Hashable {
        public var area: Area
        public var status: Status
        public var sentence: String
        public init(area: Area, status: Status, sentence: String) { self.area = area; self.status = status; self.sentence = sentence }
    }

    public var checkupAt: Date?
    public var areas: [AreaStatus]
    public var storageTotal: Int64?
    public var storageFree: Int64?
    public var drainPerHour: Double?
    public var writtenAt: Date

    public init(checkupAt: Date?, areas: [AreaStatus], storageTotal: Int64?, storageFree: Int64?, drainPerHour: Double?, writtenAt: Date) {
        self.checkupAt = checkupAt; self.areas = areas; self.storageTotal = storageTotal; self.storageFree = storageFree
        self.drainPerHour = drainPerHour; self.writtenAt = writtenAt
    }

    public init(checkup: Checkup?, drainPerHour: Double?, now: Date = .now) {
        self.checkupAt = checkup?.takenAt
        self.areas = checkup?.results.map { AreaStatus(area: $0.area, status: $0.status, sentence: $0.sentence) } ?? []
        let readings = checkup?.readings ?? []
        self.storageTotal = readings.first { $0.id == "storage.total" }?.value.number.map { Int64($0) }
        self.storageFree = (readings.first { $0.id == "storage.freeImportant" } ?? readings.first { $0.id == "storage.free" })?.value.number.map { Int64($0) }
        self.drainPerHour = drainPerHour
        self.writtenAt = now
    }

    public static func load(from url: URL = SharedContainer.snapshotURL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSON.decode(WidgetSnapshot.self, data)
    }

    public func save(to url: URL = SharedContainer.snapshotURL) throws {
        try JSON.encode(self).write(to: url, options: .atomic)
    }
}

/// Keys for documents in `VitalsStore`.
public enum DocKey {
    public static let latestCheckup = "checkup.latest"
    public static let batteryHealth = "battery.health"
    public static let hardwareTests = "hardware.results"
    public static let benchmark = "benchmark.latest"
    public static let benchmarkHistory = "benchmark.history"
    public static let networkTest = "network.latest"
    public static let repairNotes = "report.repairNotes"
    public static let sessions = "monitor.sessions"
    public static let analyticsDays = "analytics.days"
    public static let userFacts = "case.facts"
    public static let actions = "advice.actions"
    public static let caseRecord = "case.record"
    public static let companionRates = "companion.rates"
    public static let companionTotals = "companion.totals"
    public static let batteryShares = "battery.screenshotShares"
}

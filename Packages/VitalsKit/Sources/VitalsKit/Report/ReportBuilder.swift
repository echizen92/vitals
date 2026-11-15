import Foundation

/// Assembles the report from what the app holds.
public enum ReportBuilder {
    public struct Input: Sendable {
        public var checkup: Checkup?
        public var samples: [Sample]
        public var events: [LogEvent]
        public var imports: [ImportRecord]
        public var hardwareTests: [HardwareTestResult]
        public var benchmark: BenchmarkResult?
        public var repairNotes: String?
        public var processSamples: [VitalsReport.ProcessSample]
        public var now: Date
        public var appVersion: String
        public var caseRecord: CaseRecord? = nil
        public var actions: [ActionRecord] = []
        public var userFacts: [UserFact] = []

        public init(checkup: Checkup?, samples: [Sample], events: [LogEvent], imports: [ImportRecord], hardwareTests: [HardwareTestResult],
                    benchmark: BenchmarkResult?, repairNotes: String?, processSamples: [VitalsReport.ProcessSample] = [], now: Date = .now, appVersion: String) {
            self.checkup = checkup; self.samples = samples; self.events = events; self.imports = imports; self.hardwareTests = hardwareTests
            self.benchmark = benchmark; self.repairNotes = repairNotes; self.processSamples = processSamples; self.now = now; self.appVersion = appVersion
        }
    }

    public static func build(_ i: Input, redaction: RedactionOptions) -> VitalsReport {
        let readings = i.checkup?.readings ?? []
        func text(_ id: String) -> String? { readings.first { $0.id == id }?.value.text }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = text("software.os") ?? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (no check-up run)"
        let device = VitalsReport.Device(
            model: text("software.model") ?? DeviceIdentity.modelName,
            modelIdentifier: text("software.modelIdentifier") ?? DeviceIdentity.modelIdentifier,
            osVersion: os,
            osBuild: text("software.build"),
            name: text("software.deviceName"))
        // A week of samples is plenty for a report and keeps the JSON small.
        let weekAgo = i.now.addingTimeInterval(-7 * 86_400)
        let samples = i.samples.filter { $0.takenAt >= weekAgo && $0.source != .fixture }
        let report = VitalsReport(
            generatedAt: i.now,
            generator: "Vitals iOS \(i.appVersion)",
            device: device,
            readings: readings,
            samples: samples,
            hotSpells: HotSpellDetector.detect(samples),
            findings: i.checkup?.findings ?? [],
            hardwareTests: i.hardwareTests,
            imports: i.imports,
            events: i.events,
            processSamples: i.processSamples.isEmpty ? nil : i.processSamples,
            benchmark: i.benchmark,
            repairNotes: i.repairNotes?.isEmpty == false ? i.repairNotes : nil,
            statuses: i.checkup?.results.map { WidgetSnapshot.AreaStatus(area: $0.area, status: $0.status, sentence: $0.sentence) },
            caseRecord: i.caseRecord, actions: i.actions.isEmpty ? nil : i.actions, userFacts: i.userFacts.isEmpty ? nil : i.userFacts,
            couldNotDetermine: Array(Set((i.checkup?.results.flatMap { $0.couldNotDetermine ?? [] } ?? []) + (i.caseRecord?.current.couldNotDetermine ?? []))).sorted(),
            adviceVersion: AdviceCatalog.version)
        return Redactor.redact(report, redaction)
    }

    public static func json(_ report: VitalsReport) throws -> Data {
        try JSON.encode(report, pretty: true)
    }

    public static func fileStem(_ report: VitalsReport) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "Vitals-report-\(f.string(from: report.generatedAt))"
    }
}

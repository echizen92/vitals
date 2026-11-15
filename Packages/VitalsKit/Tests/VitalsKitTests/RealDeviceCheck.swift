import Foundation
import Testing
@testable import VitalsKit

/// Runs only on a developer's Mac with real (personal) logs present locally:
///   VITALS_REAL_LOGS=/path/to/crashlogs swift test --filter RealDeviceCheck
/// Nothing from those files is stored in the repository.
@Suite struct RealDeviceCheck {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VITALS_REAL_LOGS"] != nil))
    func realFolderImportsAndReachesExpectedTemporary() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VITALS_REAL_LOGS"]!)
        let files = LogImporter.ordered(LogImporter.files(in: root))
        var days: [AnalyticsDay] = [], events: [LogEvent] = []
        var kinds: [ImportKind: Int] = [:]
        for f in files {
            let r = try LogImporter.importFile(at: f, id: f.lastPathComponent, now: .now)
            kinds[r.record.kind, default: 0] += 1
            days += r.analyticsDays
            events += r.events
        }
        print("REAL: files \(files.count) kinds \(kinds.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        let d = try #require(days.max { $0.recordCount < $1.recordCount })
        print("REAL: cycle \(d.cycleCount ?? -1) thermal \(d.thermalPressureSeconds) installs \(d.successfulInstalls) wdog \(d.watchdogResets) setup \(d.setupDataSource ?? "-") top \(d.diskWrites.prefix(3).map { "\($0.process) \(Int($0.bytesWritten / 1e9))GB" })")
        print("REAL: diskwrites reports \(events.filter { $0.kind == .diskWrites && !$0.isDayPrecision }.map { "\($0.process) \($0.detail ?? "")" }.prefix(6))")
        let c = CaseEngine.evaluate(CaseInput(days: days, events: events, now: d.date.addingTimeInterval(3 * 3600)))
        print("REAL: verdict \(c.primary?.title ?? "-") / \(c.hypotheses.map(\.id))")
        #expect(d.cycleCount == 1)
        #expect(c.primary?.id == "context.newPhone")
    }
}

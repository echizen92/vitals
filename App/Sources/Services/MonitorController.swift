import Foundation
import ActivityKit
import VitalsKit

/// Runs a "watch my phone" session: a Live Activity updated locally while Vitals has runtime.
/// No push server, so when iOS suspends the app the activity keeps its last values and shows their time.
@MainActor
@Observable
final class MonitorController {
    private(set) var active: (purpose: String, start: Date)?
    private(set) var lastError: String?
    private var activity: Activity<MonitorAttributes>?
    private var loop: Task<Void, Never>?
    private var peak: ThermalLevel = .nominal

    var activitiesAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(purpose: String, model: AppModel) async {
        guard active == nil else { return }
        let start = Date.now
        active = (purpose, start)
        peak = model.thermal
        lastError = nil
        let state = MonitorAttributes.ContentState(thermal: model.thermal, batteryLevel: model.samples.last?.batteryLevel, drainPerHour: nil,
                                                    updatedAt: start, peak: model.thermal, summary: nil)
        do {
            activity = try Activity.request(attributes: MonitorAttributes(purpose: purpose, startedAt: start),
                                            content: .init(state: state, staleDate: start.addingTimeInterval(30 * 60)))
        } catch {
            // The session still records samples in the app even if the Live Activity is not allowed.
            lastError = "The Live Activity could not start (\(error.localizedDescription)). Vitals will still record the session while open."
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(model: model)
                try? await Task.sleep(for: .seconds(60))
                // Sessions end themselves after four hours.
                if let s = self?.active?.start, Date.now.timeIntervalSince(s) > 4 * 3600 { await self?.stop(model: model); return }
            }
        }
    }

    func tick(model: AppModel) async {
        guard let active else { return }
        await model.takeSample(source: .liveActivity)
        let now = Date.now
        peak = max(peak, model.thermal)
        let drain = BatteryMath.drainPerHour(model.samples.filter { $0.takenAt >= active.start }, now: now,
                                             window: now.timeIntervalSince(active.start) + 60, minSpan: 5 * 60)
        let state = MonitorAttributes.ContentState(thermal: model.thermal, batteryLevel: model.samples.last?.batteryLevel, drainPerHour: drain,
                                                    updatedAt: now, peak: peak, summary: nil)
        // Activity is safe to update from any context; ActivityKit serialises updates itself.
        if let a = activity { nonisolated(unsafe) let a = a; await a.update(.init(state: state, staleDate: now.addingTimeInterval(30 * 60))) }
    }

    /// Sessions whose app was quit or killed: end their Live Activity and save what was recorded.
    func recoverOrphans(model: AppModel) async {
        guard active == nil else { return }
        for orphan in Activity<MonitorAttributes>.activities {
            let start = orphan.attributes.startedAt
            let end = model.samples.filter { $0.takenAt >= start && $0.source == .liveActivity }.last?.takenAt ?? start
            let record = MonitorSessionRecord.summarize(purpose: orphan.attributes.purpose, start: start, end: max(end, start.addingTimeInterval(60)),
                                                        samples: model.samples)
            await model.saveSession(record)
            nonisolated(unsafe) let a = orphan
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    func stop(model: AppModel) async {
        guard let active else { return }
        loop?.cancel()
        await model.takeSample(source: .liveActivity)
        let record = MonitorSessionRecord.summarize(purpose: active.purpose, start: active.start, end: .now, samples: model.samples)
        await model.saveSession(record)
        let final = MonitorAttributes.ContentState(thermal: model.thermal, batteryLevel: model.samples.last?.batteryLevel,
                                                    drainPerHour: record.drainPerHour, updatedAt: .now, peak: record.peak,
                                                    summary: "Done: \(record.summaryLine).")
        if let a = activity { nonisolated(unsafe) let a = a; await a.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(20 * 60))) }
        activity = nil
        self.active = nil
    }
}

import SwiftUI
import Observation
import WidgetKit
import VitalsKit
import VitalsDesign

enum AppTab: String, Hashable, CaseIterable {
    case checkup, heat, optimise, logs, tests
}

/// Per-area scan progress, driven by real probe completion.
struct ScanState: Equatable {
    enum Phase: Equatable { case idle, running, done }
    var phase: Phase = .idle
    var started: Set<Area> = []
    var finished: [Area: Status] = [:]
    var startedAt: Date?
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // Navigation
    var tab: AppTab = .checkup
    var selectedArea: Area?
    var pendingScan = false
    var showGallery = false

    // Data
    var store: VitalsStore?
    private(set) var storeError: String?
    var checkup: Checkup?
    var scan = ScanState()
    var samples: [Sample] = []
    var thermal: ThermalLevel = ThermalLevel(ProcessInfo.processInfo.thermalState)
    var imports: [ImportRecord] = []
    var events: [LogEvent] = []
    var batteryHealth: BatteryHealth?
    var benchmark: BenchmarkResult?
    let isDuo = DeviceIdentity.isDuo
    var hardwareResults: [HardwareTestResult] = []
    var repairNotes = ""
    var sessions: [MonitorSessionRecord] = []
    var networkResult: NetworkTestResult?
    let monitor = MonitorController()
    // Case (plan §4a/§4b), advice and relief (§5.14, §5.14a)
    var analyticsDays: [AnalyticsDay] = []
    var facts: [UserFact] = []
    var actions: [ActionRecord] = []
    var caseRecord: CaseRecord?
    var companionRates: [ProcessRate] = []
    var companionTotals: [ProcessTotal] = []
    var batteryShares: BatteryScreenshotParser.Result?
    var showReport = false
    var showRelief = false
    var openPhotoCleanup = false
    /// A relief shortcut handed to Shortcuts; measured when Shortcuts calls back.
    var pendingRelief: (actionID: String, before: MetricsSnapshot)?
    var reliefMessage: String?

    func runReliefShortcut(_ s: ReliefShortcut, undo: Bool = false) async {
        if !undo { pendingRelief = (s.actionID, await snapshot()) }
        guard let url = s.runURL(undo: undo) else { return }
        let opened = await UIApplication.shared.open(url)
        if !opened { reliefMessage = "Shortcuts did not open. Is the Shortcuts app installed?" }
    }

    /// Simulator and debug only: values injected in place of live probes so every state can be seen.
    var injected: FixedSystemSource? {
        didSet { saveInjection() }
    }

    var source: any SystemSource { injected ?? LiveSystemSource() }
    var isInjecting: Bool { injected != nil }

    private var observers: [NSObjectProtocol] = []

    init() {
        do { store = try VitalsStore() } catch { storeError = String(describing: error) }
        injected = Self.loadInjection()
        observeSystem()
    }

    // MARK: Lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task {
                await loadAll()
                await monitor.recoverOrphans(model: self)
                await drainInbox()
                await takeSample(source: .app)
                await evaluateDueActions()
                // The "Run check-up" control or Shortcut leaves a flag in the app group.
                if PendingAction.takeScanRequest() { pendingScan = true; tab = .checkup; selectedArea = nil }
                if pendingScan { pendingScan = false; await runCheckup() }
            }
        case .background:
            BackgroundSampler.schedule()
        default: break
        }
    }

    func loadAll() async {
        guard let store else { return }
        checkup = try? await store.get(Checkup.self, key: DocKey.latestCheckup)
        batteryHealth = try? await store.get(BatteryHealth.self, key: DocKey.batteryHealth)
        benchmark = try? await store.get(BenchmarkResult.self, key: DocKey.benchmark)
        hardwareResults = (try? await store.get([HardwareTestResult].self, key: DocKey.hardwareTests)) ?? []
        repairNotes = (try? await store.get(String.self, key: DocKey.repairNotes)) ?? ""
        sessions = (try? await store.get([MonitorSessionRecord].self, key: DocKey.sessions)) ?? []
        networkResult = try? await store.get(NetworkTestResult.self, key: DocKey.networkTest)
        analyticsDays = (try? await store.get([AnalyticsDay].self, key: DocKey.analyticsDays)) ?? []
        facts = (try? await store.get([UserFact].self, key: DocKey.userFacts)) ?? []
        actions = (try? await store.get([ActionRecord].self, key: DocKey.actions)) ?? []
        caseRecord = try? await store.get(CaseRecord.self, key: DocKey.caseRecord)
        companionRates = (try? await store.get([ProcessRate].self, key: DocKey.companionRates)) ?? []
        companionTotals = (try? await store.get([ProcessTotal].self, key: DocKey.companionTotals)) ?? []
        batteryShares = try? await store.get(BatteryScreenshotParser.Result.self, key: DocKey.batteryShares)
        let args = ProcessInfo.processInfo.arguments
        // Simulator/debug: -openPhotoCleanup lands on Relief > Photos clean-up, for screenshots.
        if args.contains("-openPhotoCleanup"), isSimulatorOrDebug {
            tab = .optimise; showRelief = true; openPhotoCleanup = true
        }
        if args.contains("-syntheticDay"), !samples.contains(where: { $0.source == .fixture }) {
            await addSyntheticDay()
        }
        // Simulator/debug: -importPath <folder on the Mac> imports a folder once (e.g. the synthetic Duo case fixtures).
        if let i = args.firstIndex(of: "-importPath"), i + 1 < args.count, isSimulatorOrDebug {
            await reloadImports()
            let marker = "debug.imported." + args[i + 1]
            if !UserDefaults.standard.bool(forKey: marker) {
                UserDefaults.standard.set(true, forKey: marker)
                await importFiles(at: [URL(fileURLWithPath: args[i + 1])])
            }
        }
        if args.contains("-syntheticLogs"), imports.isEmpty {
            await reloadImports()
            if imports.isEmpty { await addSyntheticLogs() }
        }
        await reloadSamples()
        await reloadImports()
    }

    var isSimulatorOrDebug: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
        #endif
    }

    func reloadSamples() async {
        guard let store else { return }
        samples = (try? await store.samples(from: Date.now.addingTimeInterval(-7 * 86_400))) ?? []
    }

    func reloadImports() async {
        guard let store else { return }
        imports = (try? await store.imports()) ?? []
        events = (try? await store.events()) ?? []
    }

    // MARK: Check-up

    func diagnosisContext() -> DiagnosisInput {
        DiagnosisInput(readings: [], samples: samples, batteryHealth: batteryHealth, logEvents: events, benchmark: benchmark,
                       caseResult: caseRecord?.current)
    }

    // MARK: Case

    var caseInput: CaseInput {
        CaseInput(days: analyticsDays, events: events, facts: facts, rates: companionRates, totals: companionTotals, actions: actions)
    }

    /// Re-derives the case from all evidence; keeps the earlier verdict in history when it changes.
    func recomputeCase() async {
        let result = CaseEngine.evaluate(caseInput)
        let record = caseRecord.map { $0.revised(with: result) } ?? CaseRecord(current: result)
        caseRecord = record
        try? await store?.put(record, key: DocKey.caseRecord)
        refreshDiagnosis()
        await RecheckReminder.schedule(for: record.current)
    }

    func setFact(_ key: UserFact.Key, value: Double) async {
        facts.removeAll { $0.key == key }
        facts.append(UserFact(key: key, value: value, enteredAt: .now))
        try? await store?.put(facts, key: DocKey.userFacts)
        await recomputeCase()
    }

    // MARK: Actions (mark as done, measure before and after)

    func snapshot() async -> MetricsSnapshot {
        let storage = await source.storage()
        let sync = ["bird", "cloudd"].compactMap { p in companionRates.first { ProcessGlossary.shortName($0.process) == p }?.bytesWrittenPerMinute }
        return MetricsSnapshot(takenAt: .now, freeBytes: (storage.freeForImportant ?? storage.free).map(Double.init), thermal: thermal,
                               drainPerHour: BatteryMath.drainPerHour(samples), syncBytesPerMinute: sync.isEmpty ? nil : sync.reduce(0, +),
                               elevatedThermalSecondsDay: analyticsDays.max { $0.date < $1.date }?.elevatedThermalSeconds,
                               dayOf: analyticsDays.max { $0.date < $1.date }?.date)
    }

    @discardableResult
    func markDone(_ action: AdviceCatalog.Action, finding: String?, performedBy: String? = nil, before: MetricsSnapshot? = nil) async -> ActionRecord {
        let b: MetricsSnapshot
        if let before { b = before } else { b = await snapshot() }
        let rec = ActionRecord(actionID: action.id, title: action.title, findingID: finding, doneAt: .now, watch: action.watch, before: b,
                               verdict: action.watch == .none ? .unmeasurable : .pending, performedBy: performedBy ?? action.relief.rawValue)
        actions.append(rec)
        try? await store?.put(actions, key: DocKey.actions)
        await evaluateDueActions()
        await recomputeCase()
        return rec
    }

    /// Compares pending actions whose follow-up time has come.
    func evaluateDueActions() async {
        var changed = false
        let now = await snapshot()
        for (i, a) in actions.enumerated() where a.verdict == .pending && a.dueAt <= .now {
            let r = a.evaluated(with: now)
            if r.verdict != .pending || r.outcomeText != a.outcomeText { actions[i] = r; changed = true }
        }
        if changed { try? await store?.put(actions, key: DocKey.actions) }
    }

    func outcome(for actionID: String) -> ActionRecord? {
        actions.filter { $0.actionID == actionID }.max { $0.doneAt < $1.doneAt }
    }


    func runCheckup() async {
        guard scan.phase != .running else { return }
        await takeSample(source: .app)
        scan = ScanState(phase: .running, startedAt: .now)
        let context = diagnosisContext()
        let runner = CheckupRunner(source: source)
        for await event in runner.run(context: { context }) {
            switch event {
            case .areaStarted(let a):
                scan.started.insert(a)
            case .areaFinished(let area, let readings):
                // A provisional status from this area's readings alone, so the model lights as each probe lands.
                var input = context
                input.readings = readings
                scan.finished[area] = DiagnosisEngine.evaluate(area, input).status
            case .finished(let c):
                checkup = c
                for r in c.results { scan.finished[r.area] = r.status }
                scan.phase = .done
                // A check-up on injected values is shown but never saved or handed to widgets.
                if !isInjecting {
                    try? await store?.put(c, key: DocKey.latestCheckup)
                    writeWidgetSnapshot()
                }
            }
        }
    }

    func writeWidgetSnapshot() {
        let snapshot = WidgetSnapshot(checkup: checkup, drainPerHour: BatteryMath.drainPerHour(samples))
        try? snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Sampling

    func takeSample(source sampleSource: SampleSource) async {
        // Samples taken while values are injected are stored as fixtures, never as real readings.
        let s = await CheckupRunner(source: source).sample(source: isInjecting ? .fixture : sampleSource)
        thermal = s.thermal
        try? await store?.insert(s)
        try? await store?.pruneSamples()
        await reloadSamples()
        await HeatAlerts.shared.consider(s)
    }

    private func observeSystem() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.takeSample(source: .app) }
        })
        observers.append(nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.takeSample(source: .app) }
        })
        observers.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.takeSample(source: .app) }
        })
    }

    func addSyntheticDay() async {
        try? await store?.deleteSamples(source: .fixture)
        try? await store?.insert(SyntheticSamples.day())
        await reloadSamples()
    }

    /// Simulator: writes synthetic reports timed to the latest hot spell and imports them.
    func addSyntheticLogs() async {
        if !samples.contains(where: { $0.source == .fixture }) { await addSyntheticDay() }
        guard let spell = HotSpellDetector.detect(samples).first(where: { !$0.wasCharging }) ?? HotSpellDetector.detect(samples).first else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in SyntheticLogs.files(around: spell) {
            let u = dir.appendingPathComponent(f.name)
            try? f.text.write(to: u, atomically: true, encoding: .utf8)
            await importFile(at: u)
        }
    }

    func deleteAllData() async {
        try? await store?.deleteAllSamples()
        for i in imports { try? await store?.deleteImport(id: i.id) }
        try? await store?.removeDoc(key: DocKey.batteryHealth)
        ImportLibrary.deleteAllFiles()
        for k in [DocKey.analyticsDays, DocKey.userFacts, DocKey.actions, DocKey.caseRecord, DocKey.companionRates, DocKey.companionTotals, DocKey.batteryShares] {
            try? await store?.removeDoc(key: k)
        }
        analyticsDays = []; facts = []; actions = []; caseRecord = nil; companionRates = []; companionTotals = []; batteryShares = nil
        batteryHealth = nil
        await reloadSamples()
        await reloadImports()
    }

    // MARK: Performance

    func saveBenchmark(_ r: BenchmarkResult) async {
        benchmark = r
        try? await store?.put(r, key: DocKey.benchmark)
        refreshDiagnosis()
    }

    func saveNetworkResult(_ r: NetworkTestResult) async {
        networkResult = r
        try? await store?.put(r, key: DocKey.networkTest)
    }

    // MARK: Monitoring sessions

    func saveSession(_ r: MonitorSessionRecord) async {
        sessions.append(r)
        sessions = Array(sessions.suffix(50))
        try? await store?.put(sessions, key: DocKey.sessions)
    }

    // MARK: Report

    func saveRepairNotes(_ text: String) {
        repairNotes = text
        Task { try? await store?.put(text, key: DocKey.repairNotes) }
    }

    func buildReport(redaction: RedactionOptions) -> VitalsReport {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        var input = ReportBuilder.Input(checkup: checkup, samples: samples, events: events, imports: imports, hardwareTests: hardwareResults,
                                        benchmark: benchmark, repairNotes: repairNotes, appVersion: version)
        input.caseRecord = caseRecord
        input.actions = actions
        input.userFacts = facts
        return ReportBuilder.build(input, redaction: redaction)
    }

    func saveHardwareResult(_ r: HardwareTestResult) {
        // Each test result is confirmed with a haptic (plan 6, "tests as play"); fired here because the test screen closes on the same tap.
        switch r.outcome {
        case .passed: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failed: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        default: UISelectionFeedbackGenerator().selectionChanged()
        }
        hardwareResults.removeAll { $0.kind == r.kind }
        hardwareResults.append(r)
        hardwareResults.sort { HardwareTestKind.allCases.firstIndex(of: $0.kind)! < HardwareTestKind.allCases.firstIndex(of: $1.kind)! }
        let all = hardwareResults
        Task { try? await store?.put(all, key: DocKey.hardwareTests) }
    }

    // MARK: Deep links

    /// vitals://checkup, vitals://scan, vitals://heat, vitals://battery, vitals://storage, vitals://memory,
    /// vitals://network, vitals://software, vitals://logs, vitals://tests, vitals://report. File URLs are imports.
    func handle(url: URL) {
        if url.isFileURL {
            tab = .logs
            Task { await importFile(at: url) }
            return
        }
        guard url.scheme == "vitals" else { return }
        let host = url.host() ?? ""
        switch host {
        case "relief-done":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
            if let p = pendingRelief, p.actionID == id, let a = AdviceCatalog.action(p.actionID) {
                pendingRelief = nil
                Task { await markDone(a, finding: nil, performedBy: "shortcut", before: p.before); reliefMessage = "\(a.title): done. Vitals will report the result." }
            } else if id?.hasPrefix("undo.") == true { reliefMessage = "Undone." }
        case "relief-cancel", "relief-error":
            pendingRelief = nil
            if host == "relief-cancel" {
                reliefMessage = "Cancelled in Shortcuts. Nothing changed."
            } else {
                // Vitals cannot see which shortcuts are installed, so point at the row's own Add button.
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
                if let s = id.flatMap(ReliefShortcut.forCallback) {
                    reliefMessage = "Shortcuts could not run “\(s.rawValue)”. If it is not in the Shortcuts app yet, tap Add next to \(s.title) below, then Run again."
                } else {
                    reliefMessage = "Shortcuts reported an error. If the shortcut is not in the Shortcuts app yet, tap its Add button below, then Run again."
                }
            }
        case "scan":
            tab = .checkup; selectedArea = nil
            pendingScan = true
            Task { if pendingScan { pendingScan = false; await runCheckup() } }
        case "checkup": tab = .checkup; selectedArea = nil
        case "heat": tab = .heat
        case "logs": tab = .logs
        case "tests": tab = .tests
        case "report": tab = .checkup; showReport = true
        case "optimise", "relief": tab = .optimise; showRelief = host == "relief"
        case "gallery": tab = .checkup; showGallery = true
        default:
            if let area = Area(rawValue: host) { tab = .checkup; selectedArea = area }
        }
    }

    // MARK: Injection (simulator and debug)

    private static let injectionKey = "debug.injectedSource"

    private func saveInjection() {
        // A launch-argument injection is for that run only (and @Observable runs didSet during init).
        guard !ProcessInfo.processInfo.arguments.contains("-inject") else { return }
        if let injected, let data = try? JSONEncoder().encode(injected) {
            UserDefaults.standard.set(data, forKey: Self.injectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.injectionKey)
        }
    }

    private static func loadInjection() -> FixedSystemSource? {
        // Launch argument for screenshots and UI checks: -inject hot|critical|lowStorage|…; wins over the saved choice.
        if let fromArgs = InjectionPresets.fromLaunchArguments() { return fromArgs }
        if ProcessInfo.processInfo.arguments.contains("-live") {
            UserDefaults.standard.removeObject(forKey: injectionKey)
            return nil
        }
        guard let data = UserDefaults.standard.data(forKey: injectionKey) else { return nil }
        return try? JSONDecoder().decode(FixedSystemSource.self, from: data)
    }

    // MARK: Imports

    var importing: ImportProgress?
    var lastImport: ImportOutcome?

    struct ImportProgress: Equatable { var fileName: String; var fraction: Double }
    struct ImportOutcome: Equatable, Identifiable {
        var id = UUID()
        var fileName: String
        var message: String
        var failed: Bool
    }

    /// Imports one file, or every report in a folder (newest daily analytics file first).
    func importFiles(at urls: [URL]) async {
        var all: [URL] = []
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            all += LogImporter.files(in: u)
            if scoped { u.stopAccessingSecurityScopedResource() }
        }
        for u in LogImporter.ordered(all.isEmpty ? urls : all) { await importFile(at: u) }
    }

    func importFile(at url: URL) async {
        importing = ImportProgress(fileName: url.lastPathComponent, fraction: 0)
        defer { importing = nil }
        do {
            let result = try await ImportLibrary.ingest(url: url) { f in
                Task { @MainActor in AppModel.shared.importing?.fraction = f }
            }
            try await store?.save(result.record, events: result.events)
            if let h = result.batteryHealth, batteryHealth.map({ h.asOf >= $0.asOf }) ?? true {
                batteryHealth = h
                try? await store?.put(h, key: DocKey.batteryHealth)
            }
            if !result.samples.isEmpty { try? await store?.insert(result.samples) }
            if !result.analyticsDays.isEmpty {
                for d in result.analyticsDays {
                    analyticsDays.removeAll { Calendar.current.isDate($0.date, inSameDayAs: d.date) && $0.recordCount <= d.recordCount }
                    if !analyticsDays.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: d.date) }) { analyticsDays.append(d) }
                }
                analyticsDays.sort { $0.date < $1.date }
                try? await store?.put(analyticsDays, key: DocKey.analyticsDays)
            }
            if !result.processRates.isEmpty {
                companionRates = result.processRates
                try? await store?.put(companionRates, key: DocKey.companionRates)
            }
            if !result.processTotals.isEmpty {
                companionTotals = result.processTotals
                try? await store?.put(companionTotals, key: DocKey.companionTotals)
            }
            if !result.processSamples.isEmpty { try? await store?.put(result.processSamples, key: "companion.processes.\(result.record.id)") }
            await reloadImports()
            await reloadSamples()
            await evaluateDueActions()
            await recomputeCase()
            lastImport = ImportOutcome(fileName: result.record.fileName, message: Self.describe(result), failed: false)
        } catch {
            lastImport = ImportOutcome(fileName: url.lastPathComponent, message: String(describing: error), failed: true)
        }
    }

    static func describe(_ r: ImportResult) -> String {
        var parts = ["Read as: \(r.record.kind.label)."]
        if r.record.eventCount > 0 { parts.append("\(r.record.eventCount) events.") }
        if let h = r.batteryHealth {
            if let m = h.effectiveMaxCapacity { parts.append("Battery maximum capacity \(Int(m.value.rounded()))%.") }
            if let c = h.cycleCount { parts.append("\(c) cycles.") }
        }
        if !r.samples.isEmpty { parts.append("\(r.samples.count) samples added to the timeline.") }
        return parts.joined(separator: " ")
    }

    /// Files the share extension left in the app group.
    func drainInbox() async {
        for url in ImportLibrary.inboxFiles() {
            await importFile(at: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func deleteImport(_ record: ImportRecord) async {
        try? await store?.deleteImport(id: record.id)
        analyticsDays.removeAll { $0.sourceFile == record.fileName }
        try? await store?.put(analyticsDays, key: DocKey.analyticsDays)
        ImportLibrary.delete(record)
        if batteryHealth?.sourceFile == record.fileName {
            batteryHealth = nil
            try? await store?.removeDoc(key: DocKey.batteryHealth)
        }
        await reloadImports()
        await recomputeCase()
    }

    /// Re-runs the rules on the last check-up's readings with fresh history (after an import, a benchmark…).
    func refreshDiagnosis() {
        guard let c = checkup else { return }
        let derived: Set<String> = ["battery.drainRate", "battery.chargeRate", "battery.maxCapacity", "battery.cycleCount", "heat.spells24h", "heat.samples24h"]
        var input = diagnosisContext()
        input.readings = c.readings.filter { !derived.contains($0.id) }
        input.now = c.takenAt
        checkup = Checkup(takenAt: c.takenAt, results: DiagnosisEngine.evaluate(input))
        if !isInjecting {
            Task { try? await store?.put(checkup, key: DocKey.latestCheckup) }
            writeWidgetSnapshot()
        }
    }

    func record(for event: LogEvent) -> ImportRecord? {
        imports.first { $0.id == event.importID }
    }
}

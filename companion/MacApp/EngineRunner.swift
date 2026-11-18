import SwiftUI
import VitalsKit

// Vitals Companion for Mac. GPL-3.0-or-later (companion/LICENSE): it drives pymobiledevice3.
// The model: runs the Python engine (companion/engine) as a subprocess and turns its JSON event
// stream into state the views draw.

/// What the Mac can read from the phone (plan 4c), from `vitals_companion check`.
struct AccessCheck: Decodable {
    var tier: Int
    var connection: String?
    var developerMode: Bool?
    var canRead: [String]
    var cannotRead: [String]
    var explain: [String]
    var device: [String: String]?
    /// Every iPhone this Mac can reach now (never the UDID: `ref` is the engine's short hash).
    var devices: [Phone]?
    var chosen: String?
    var chosenMissing: Bool?
}

/// One reachable iPhone, from `vitals_companion check`.
struct Phone: Decodable, Identifiable, Hashable {
    var id: String { ref }
    let ref: String
    let model: String?
    let os: String?
    let connection: String?

    var modelName: String { model.flatMap { Catalog.modelName(for: $0) } ?? "iPhone" }
    var connectionName: String { connection == "wifi" ? "Wi-Fi" : "USB" }
    /// "iPhone Duo · USB"
    var label: String { "\(modelName) · \(connectionName)" }
}

struct RateRow: Identifiable, Decodable {
    var id: String { process }
    let process: String
    let bytesWrittenPerMinute: Double
    let cpuPercent: Double?
}

struct CompareRow: Identifiable, Decodable {
    var id: String { process }
    let process: String
    let beforeMBPerMinute: Double?
    let afterMBPerMinute: Double?
}

/// The one thing the window is doing.
enum Job: String { case home, logs, live, fix }

/// Where that thing has got to.
enum Phase: Equatable {
    case ready          // choosing options, nothing running
    case working        // pulling logs, capturing, or measuring "before"
    case yourTurn       // before/after: the person does the action on the phone
    case settling       // before/after: waiting for the phone to calm down
    case after          // before/after: measuring "after"
    case finished
    case failed(String)
}

/// Runs `python -m vitals_companion …` and parses its JSON event stream.
@MainActor
@Observable
final class EngineRunner {
    struct TempPoint: Identifiable { let id = UUID(); let t: Date; let c: Double }
    struct Proc: Identifiable { var id: String { name }; let name: String; var cpu: Double; var seen: Date }

    // Preferences
    /// Development only. Never read when the app carries its own runtime (the downloadable build).
    var pythonOverride: String {
        get { bundledPython == nil ? (UserDefaults.standard.string(forKey: "python") ?? "") : "" }
        set { if bundledPython == nil { UserDefaults.standard.set(newValue, forKey: "python") } }
    }

    /// Contents/Resources/python/bin/python3 in the downloadable build (pinned CPython with pymobiledevice3).
    var bundledPython: String? {
        guard let r = Bundle.main.resourceURL?.appendingPathComponent("python/bin/python3"),
              FileManager.default.isExecutableFile(atPath: r.path) else { return nil }
        return r.path
    }
    var simulate = UserDefaults.standard.bool(forKey: "simulate") { didSet { UserDefaults.standard.set(simulate, forKey: "simulate"); check() } }
    var wifi = false { didSet { check() } }
    /// The phone the person picked, remembered between launches. Nil: the engine prefers a USB phone.
    var chosenPhone: String? = UserDefaults.standard.string(forKey: "phone") {
        didSet { UserDefaults.standard.set(chosenPhone, forKey: "phone"); if chosenPhone != oldValue { check() } }
    }
    /// The phone the current or last task measured, named on the result.
    var measuredPhone: Phone?
    var saveFolderPath: String = UserDefaults.standard.string(forKey: "saveFolder") ?? "" {
        didSet { UserDefaults.standard.set(saveFolderPath, forKey: "saveFolder") }
    }

    // Connection
    var access: AccessCheck?
    var checking = false
    var checkProblem: String?
    var device: [String: String] = [:]

    // What the window is doing
    var task: Job = .home
    var phase: Phase = .ready { didSet { if phase != oldValue { announce(phase) } } }
    var phaseStart: Date?
    var phaseLength: TimeInterval?

    // Readings
    var temps: [TempPoint] = []
    var batteryLevel: Double?
    var charging: Bool?
    var adapterWatts: Double?
    var procs: [String: Proc] = [:]
    var warnings: [String] = []
    var rates: [RateRow] = []
    /// What the measuring itself cost the phone, percent of one core averaged per reading (engine "cost" event).
    var measurementCost: Double?
    var comparison: [CompareRow] = []
    var verdict: String?

    /// The engine's verdict with friendly process names ("iCloud Drive", not "bird") and plain wording.
    var plainVerdict: String? {
        guard var v = verdict else { return nil }
        for row in comparison.sorted(by: { $0.process.count > $1.process.count }) {
            guard let e = ProcessGlossary.entry(for: row.process) else { continue }
            v = v.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: row.process))\\b", with: e.name, options: .regularExpression)
        }
        return v.replacingOccurrences(of: "after the action", with: "after the change")
                .replacingOccurrences(of: "The action ", with: "The change ")
                .replacingOccurrences(of: "before the action", with: "before the change")
    }
    var actionPrompt: String?
    var fixAction: String?
    var logFileCount: Int?
    var lastOutput: URL?

    private var process: Process?
    private var stdin: Pipe?
    private var buffer = Data()

    var running: Bool {
        switch phase {
        case .working, .yourTurn, .settling, .after: true
        default: false
        }
    }

    /// 0 no phone, 1 logs and battery, 2 everything.
    var tier: Int { access?.tier ?? 0 }
    var connected: Bool { tier >= 1 }
    var latestTemp: Double? { temps.last?.c }

    /// Bundled runtime first (release), then the Settings override, then the development venv, then the system.
    var python: String {
        if let b = bundledPython { return b }
        if !pythonOverride.isEmpty { return pythonOverride }
        let venv = engineDir.appendingPathComponent(".venv/bin/python3")
        if FileManager.default.isExecutableFile(atPath: venv.path) { return venv.path }
        return "/usr/bin/python3"
    }

    var engineDir: URL {
        if let r = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: r.appendingPathComponent("vitals_companion").path) { return r }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("engine")
    }

    /// Results go in one folder the person can change in Settings, never scattered on the Desktop.
    var saveFolder: URL {
        if !saveFolderPath.isEmpty { return URL(fileURLWithPath: saveFolderPath) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Vitals")
    }

    /// All reachable phones, and the one the engine is using.
    var phones: [Phone] { access?.devices ?? [] }
    var currentPhone: Phone? { phones.first { $0.ref == access?.chosen } ?? phones.first }

    var topProcesses: [Proc] { procs.values.filter { Date().timeIntervalSince($0.seen) < 25 }.sorted { $0.cpu > $1.cpu }.prefix(6).map { $0 } }

    // MARK: Engine

    private func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        // The engine picks the phone by `--device <ref>`, resolves it to the UDID itself and never prints that.
        let pick = (!simulate ? chosenPhone : nil).map { ["--device", $0] } ?? []
        p.arguments = ["-m", "vitals_companion"] + (simulate ? ["--simulate"] : []) + (wifi ? ["--wifi"] : []) + pick + args
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = engineDir.path
        env["PYTHONUNBUFFERED"] = "1"
        let bin = URL(fileURLWithPath: python).deletingLastPathComponent().path
        if bundledPython != nil {
            // The downloadable build uses nothing outside the app: its own Python and pymobiledevice3, and the
            // system's /usr/bin (xcrun, for the optional devicectl log pull). No user site-packages.
            env["PATH"] = bin + ":/usr/bin:/bin:/usr/sbin:/sbin"
            env["VITALS_PMD3"] = bin + "/pymobiledevice3"
            env["PYTHONNOUSERSITE"] = "1"
            env["PYTHONDONTWRITEBYTECODE"] = "1"   // the bundle is signed; bytecode was compiled before signing
            env.removeValue(forKey: "PYTHONHOME")
        } else {
            // Development: pymobiledevice3 next to the chosen python, or on the usual install paths.
            env["PATH"] = bin + ":" + (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
            if env["VITALS_PMD3"] == nil, FileManager.default.isExecutableFile(atPath: bin + "/pymobiledevice3") { env["VITALS_PMD3"] = bin + "/pymobiledevice3" }
        }
        p.environment = env
        return p
    }

    /// One-shot command that prints JSON.
    private func runJSON(_ args: [String], done: @escaping @MainActor (Data, Int32, String) -> Void) {
        let p = makeProcess(args)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.terminationHandler = { proc in
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let code = proc.terminationStatus
            Task { @MainActor in done(o, code, e) }
        }
        do { try p.run() } catch { done(Data(), -1, error.localizedDescription) }
    }

    private func lastLine(_ s: String) -> String? {
        s.split(separator: "\n").last.map(String.init)
    }

    func check() {
        checking = true
        checkProblem = nil
        runJSON(["check"]) { data, code, err in
            self.checking = false
            self.access = try? JSONDecoder().decode(AccessCheck.self, from: data)
            if self.access == nil { self.checkProblem = self.lastLine(err) ?? "The check did not finish." }
            // Exit 3: the engine could not start pymobiledevice3. Say that, not "no iPhone found".
            if code == 3 { self.checkProblem = self.access?.explain.first ?? "pymobiledevice3 is missing." }
            if let d = self.access?.device { self.device = d }
            // A remembered phone that is not here now: forget it, so the next check uses the preferred one.
            if self.access?.chosenMissing == true { self.addWarning("The iPhone you chose last time is not connected; using \(self.currentPhone?.label ?? "another iPhone").") }
        }
    }

    private func output(_ prefix: String) -> URL {
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"   // 24-hour, sorts by name, no colons (Finder shows them as slashes)
        let stamp = f.string(from: .now)
        return saveFolder.appendingPathComponent("\(prefix) \(stamp)")
    }

    // MARK: Tasks

    func open(_ t: Job) {
        guard !running else { return }
        resetReadings()
        task = t
        phase = .ready
        if t == .logs { pullLogs() }
    }

    func goHome() {
        guard !running else { return }
        task = .home
        phase = .ready
    }

    /// First action for most people: every crash and analytics log, no Developer Mode, no Xcode.
    func pullLogs() {
        guard !running else { return }
        resetReadings()
        task = .logs
        let out = output("Logs")
        begin(.working, length: nil)
        runJSON(["pull", "logs", "--out", out.path]) { data, code, err in
            if code == 0, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.lastOutput = out
                self.logFileCount = obj["files"] as? Int
                self.phase = .finished
            } else {
                self.phase = .failed(self.lastLine(err) ?? "The phone did not hand over its logs.")
            }
        }
    }

    func startCapture(minutes: Double) {
        guard !running else { return }
        resetReadings()
        task = .live
        let seconds = minutes * 60
        let out = output("Capture")
        stream(["capture", "--events", "--seconds", "\(Int(seconds))", "--interval", "10", "--snapshot-every", "120", "--out", out.path]
               + (simulate ? ["--speed", "1"] : []))
        begin(.working, length: seconds)
    }

    /// The simulated phone measures 20-second windows so a test run takes under a minute; its counters run
    /// 30 times faster, so the rates still look like a real 5-minute window.
    func startFixTest(action: String, windowMinutes: Double) {
        guard !running else { return }
        resetReadings()
        task = .fix
        fixAction = action
        let out = output("Before and after")
        let window = simulate ? 20 : Int(windowMinutes * 60)
        stream(["around-action", "--events", "--wait", "--action", action, "--window", "\(window)", "--settle", simulate ? "0" : "60", "--out", out.path]
               + (simulate ? ["--speed", "30"] : []), wantsInput: true)
        lastOutput = out
        begin(.working, length: TimeInterval(window))
    }

    func actionDone() {
        actionPrompt = nil
        begin(.settling, length: simulate ? nil : 60)
        stdin?.fileHandleForWriting.write(Data("\n".utf8))
    }

    func stop() { process?.terminate() }

    private func begin(_ p: Phase, length: TimeInterval?) {
        if p == .working, !running { measuredPhone = currentPhone }
        phase = p
        phaseStart = .now
        phaseLength = length
    }

    private func resetReadings() {
        temps = []; procs = [:]; warnings = []; rates = []; comparison = []; verdict = nil; lastOutput = nil; measurementCost = nil
        actionPrompt = nil; logFileCount = nil; batteryLevel = nil; charging = nil; adapterWatts = nil
        buffer = Data()
    }

    private func stream(_ args: [String], wantsInput: Bool = false) {
        let p = makeProcess(args)
        let pipe = Pipe(), err = Pipe()
        p.standardOutput = pipe; p.standardError = err
        if wantsInput { let i = Pipe(); p.standardInput = i; stdin = i }
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { @MainActor in self.consume(d) }
        }
        p.terminationHandler = { proc in
            let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let code = proc.terminationStatus
            Task { @MainActor in
                // Let the last events drain before deciding how it ended.
                try? await Task.sleep(for: .milliseconds(150))
                guard self.running else { return }
                if code == 0 || code == 15 { self.phase = self.lastOutput == nil ? .ready : .finished }
                else { self.phase = .failed(self.lastLine(e) ?? "The measurement stopped unexpectedly.") }
            }
        }
        do { try p.run(); process = p } catch { phase = .failed("Could not start the measuring engine: \(error.localizedDescription)") }
    }

    private func addWarning(_ w: String) {
        if !warnings.contains(w) { warnings.append(w) }
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0a) {
            let line = buffer.prefix(upTo: nl)
            buffer.removeSubrange(...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = obj["type"] as? String else { continue }
            switch type {
            case "device":
                device = (obj["info"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            case "battery":
                if let c = obj["temperatureC"] as? Double, let t = obj["t"] as? Double { temps.append(TempPoint(t: Date(timeIntervalSince1970: t), c: c)) }
                if let l = obj["level"] as? Double { batteryLevel = l }
                if let c = obj["charging"] as? Bool { charging = c }
                if let w = obj["adapterWatts"] as? Double { adapterWatts = w }
            case "process":
                if let n = obj["name"] as? String, let c = obj["cpu"] as? Double { procs[n] = Proc(name: n, cpu: c, seen: .now) }
            case "cost":
                measurementCost = (obj["totalPercent"] as? Double) ?? (obj["totalPercent"] as? Int).map(Double.init)
            case "warning":
                if let m = obj["message"] as? String { addWarning(m) }
            case "window":
                if obj["phase"] as? String == "started" {
                    let seconds = (obj["seconds"] as? Double) ?? Double(obj["seconds"] as? Int ?? 0)
                    let real = seconds > 0 ? seconds : nil   // the engine sleeps in real time, simulated or not
                    if obj["label"] as? String == "after" { actionPrompt = nil; begin(.after, length: real) }
                    else { begin(.working, length: real) }
                }
            case "action":
                actionPrompt = obj["message"] as? String
                begin(.yourTurn, length: nil)
            case "result":
                if let r = obj["result"] as? [String: Any] {
                    verdict = r["verdict"] as? String
                    if let rows = try? JSONSerialization.data(withJSONObject: r["comparison"] ?? []) { comparison = (try? JSONDecoder().decode([CompareRow].self, from: rows)) ?? [] }
                    for w in r["warnings"] as? [String] ?? [] { addWarning(w) }
                    phase = .finished
                }
            case "done":
                if let p = obj["path"] as? String {
                    let url = URL(fileURLWithPath: p)
                    lastOutput = url
                    if let data = try? Data(contentsOf: url), let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let r = try? JSONSerialization.data(withJSONObject: doc["processRates"] ?? []) {
                        rates = Array(((try? JSONDecoder().decode([RateRow].self, from: r)) ?? []).prefix(6))
                    }
                }
                for w in obj["warnings"] as? [String] ?? [] { addWarning(w) }
                if task == .live { phase = .finished }
            default: break
            }
        }
    }

    // MARK: Accessibility

    /// VoiceOver hears each step of a job without having to look for it.
    private func announce(_ p: Phase) {
        let text: String? = switch (task, p) {
        case (.logs, .working): "Collecting logs from your iPhone"
        case (.logs, .finished): "Logs collected" + (logFileCount.map { ", \($0) files" } ?? "")
        case (.live, .working): "Watching live"
        case (.live, .finished): "Live watch finished"
        case (.fix, .working): "Measuring before"
        case (.fix, .yourTurn): "Your turn. " + (fixAction ?? "Make the change") + " on your iPhone, then choose It's back."
        case (.fix, .settling): "Letting the iPhone settle"
        case (.fix, .after): "Measuring after"
        case (.fix, .finished): plainVerdict ?? "Test finished"
        case (_, .failed(let why)): "Stopped. " + why
        default: nil
        }
        if let text { AccessibilityNotification.Announcement(text).post() }
    }

    // MARK: Handing results on

    func showInFinder() {
        if let u = lastOutput { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }

    func airDrop() {
        guard let u = lastOutput else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [u])
    }
}

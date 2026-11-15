import SwiftUI
import Charts
import VitalsKit
import VitalsDesign

/// The right side: one task at a time.
struct StageView: View {
    @Environment(EngineRunner.self) private var runner
    @Environment(\.motionLevel) private var motion

    var body: some View {
        ScrollView {
            Group {
                switch runner.task {
                case .home: HomeStage()
                case .logs: LogsStage()
                case .live: LiveStage()
                case .fix: FixStage()
                }
            }
            .id(runner.task)
            // The old stage leaves quickly, then the new one slides in: no overlapping layers.
            .transition(motion == .still
                        ? .opacity.animation(Motion.fade)
                        : .asymmetric(insertion: .offset(x: 28).combined(with: .opacity).animation(Motion.settle.delay(0.1)),
                                      removal: .opacity.animation(.easeOut(duration: 0.1))))
            .padding(.horizontal, Space.xl).padding(.vertical, Space.xxl)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(VColor.ground)
        .toolbar {
            if runner.task != .home && !runner.running {
                ToolbarItem(placement: .navigation) {
                    Button { runner.goHome() } label: { Label("All tasks", systemImage: "chevron.left") }
                        .help("Back to all tasks")
                }
            }
            if runner.running {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .cancel) { runner.stop() } label: { Label("Stop", systemImage: "stop.circle") }
                        .help("Stop (⌘.)")
                }
            }
        }
    }
}

// MARK: - Home

struct HomeStage: View {
    @Environment(EngineRunner.self) private var runner

    private var lead: String {
        if runner.checkProblem != nil { return "The measuring engine needs fixing before Vitals can reach an iPhone. The left column says what is wrong." }
        if runner.checking && runner.access == nil { return "Looking for your iPhone…" }
        return switch runner.tier {
        case 2: "Your iPhone is connected with full access. Choose one thing to do."
        case 1: "Your iPhone is connected. Logs and battery are ready; live activity needs Developer Mode, which is optional."
        default: "Connect your iPhone with a cable to begin. The steps are on the left."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            StageTitle(title: "What would you like to do?", subtitle: lead)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: Space.l, alignment: .top)], alignment: .leading, spacing: Space.l) {
                TaskCard(symbol: "tray.and.arrow.down", title: "Collect logs",
                         text: "Every crash report and daily log from the iPhone, for Vitals on the iPhone to read.",
                         needs: "Needs: a connection", available: runner.tier >= 1, button: "Collect") { runner.pullLogs() }
                TaskCard(symbol: "waveform.path.ecg", title: "Watch it live",
                         text: "Battery, temperature and what is busy, as it happens.",
                         needs: runner.tier >= 2 ? "Needs: a connection" : "Needs: a connection. What is busy also needs Developer Mode.",
                         available: runner.tier >= 1, button: "Set up") { runner.open(.live) }
                TaskCard(symbol: "arrow.left.arrow.right", title: "Test a fix",
                         text: "Measure, make one change, measure again. See whether it helped.",
                         needs: runner.tier >= 2 ? "Needs: full access" : "Needs Developer Mode. Without it: make the change, then compare tomorrow in Vitals on the iPhone.",
                         available: runner.tier >= 2, button: "Set up") { runner.open(.fix) }
            }
            if let last = runner.lastOutput, runner.phase == .finished {
                Button { runner.showInFinder() } label: { Label("Last result: \(last.lastPathComponent)", systemImage: "folder") }
                    .vitalsButton(.tertiary, size: .regular)
            }
        }
    }
}

struct TaskCard: View {
    var symbol: String
    var title: String
    var text: String
    var needs: String
    var available: Bool
    var button: String
    var action: () -> Void
    @State private var hover = false
    @Environment(\.motionLevel) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(available ? VColor.ink : VColor.ink2)
                .frame(width: 48, height: 48)
                .background(Circle().fill((available ? VColor.ink : VColor.ink2).opacity(0.12)))
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(VColor.ink).accessibilityAddTraits(.isHeader)
            Text(text).font(.callout).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Label(needs, systemImage: available ? "checkmark.circle" : "info.circle")
                .font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).vitalsButton(.primary, size: .regular).disabled(!available)
                .accessibilityLabel("\(button): \(title)")
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous).fill(VColor.surface)
            .shadow(color: .black.opacity(hover && available ? 0.10 : 0.04), radius: hover && available ? 14 : 6, y: hover && available ? 6 : 2))
        .scaleEffect(hover && available && motion != .still ? 1.01 : 1)
        .animation(Motion.change(motion, Motion.snappy), value: hover)
        .onHover { hover = $0 }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Logs

struct LogsStage: View {
    @Environment(EngineRunner.self) private var runner

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            switch runner.phase {
            case .finished:
                StageTitle(title: "Logs collected", subtitle: "Send them to your iPhone and open them in Vitals. It reads the newest daily log first.")
                Card {
                    VStack(alignment: .leading, spacing: Space.l) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text("\(runner.logFileCount ?? 0)")
                                .font(.system(size: 56, weight: .semibold, design: .rounded))
                                .foregroundStyle(VColor.ink)
                                .contentTransition(.numericText(value: Double(runner.logFileCount ?? 0)))
                            Text(runner.logFileCount == 1 ? "file" : "files").font(.title2).foregroundStyle(VColor.ink2)
                        }
                        .accessibilityElement(children: .combine)
                        if let out = runner.lastOutput {
                            Label("Saved in \(Plain.savedPath(out))", systemImage: "folder").font(.callout).foregroundStyle(VColor.ink2)
                        }
                        ResultButtons()
                    }
                }
            case .failed(let why):
                FailedView(title: "The logs did not come across", why: why) { runner.pullLogs() }
            case .ready:
                EmptyView()   // only seen for a moment while leaving
            default:
                StageTitle(title: "Collecting logs…", subtitle: "This takes up to a minute. Keep the iPhone unlocked and connected.")
                Card { PhaseProgress(start: runner.phaseStart, length: nil, label: "Copying crash reports and daily logs") }
            }
        }
    }
}

// MARK: - Live

struct LiveStage: View {
    @Environment(EngineRunner.self) private var runner
    @State private var minutes = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            switch runner.phase {
            case .ready:
                StageTitle(title: "Watch it live", subtitle: "Vitals reads the iPhone every few seconds and shows what is busy. Use the iPhone as you normally would, or do the thing that makes it hot.")
                Card {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Text("For how long?").font(.headline).foregroundStyle(VColor.ink)
                        Picker("Length", selection: $minutes) {
                            Text("1 minute").tag(1.0); Text("5 minutes").tag(5.0); Text("10 minutes").tag(10.0); Text("30 minutes").tag(30.0)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .accessibilityLabel("Length")
                        if runner.tier < 2 {
                            Label("Without Developer Mode this shows battery and temperature only.", systemImage: "info.circle")
                                .font(.callout).foregroundStyle(VColor.ink2)
                        }
                        Button("Start watching") { runner.startCapture(minutes: minutes) }.vitalsButton(.primary, size: .regular)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            case .failed(let why):
                FailedView(title: "Watching stopped", why: why) { runner.open(.live) }
            default:
                LiveReadout()
            }
        }
    }
}

private struct LiveReadout: View {
    @Environment(EngineRunner.self) private var runner

    /// Verdict first: the biggest writer in one sentence.
    private var finishedLine: String {
        guard let top = runner.rates.first else {
            return runner.tier >= 2 ? "Nothing wrote enough to measure while Vitals watched." : "Battery and temperature were recorded. What was busy needs Developer Mode."
        }
        return "\(Plain.process(top.process).name) wrote the most: \(Plain.megabytesPerMinute(top.bytesWrittenPerMinute / 1e6))."
    }

    var body: some View {
        let done = runner.phase == .finished
        VStack(alignment: .leading, spacing: Space.xl) {
            StageTitle(title: done ? "Finished watching" : "Watching live", subtitle: done ? finishedLine : nil)
            if done {
                writers
            } else {
                PhaseProgress(start: runner.phaseStart, length: runner.phaseLength, label: "Reading every 3 seconds")
            }
            HStack(alignment: .top, spacing: Space.l) {
                Card { TemperatureFigure(celsius: runner.latestTemp).frame(maxHeight: .infinity, alignment: .topLeading) }
                Card { BatteryFigure(level: runner.batteryLevel, charging: runner.charging, watts: runner.adapterWatts).frame(maxHeight: .infinity, alignment: .topLeading) }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !done { busiest }
            if runner.temps.count > 1 {
                Card {
                    VStack(alignment: .leading, spacing: Space.m) {
                        SectionTitle("Battery temperature")
                        TemperatureChart(points: runner.temps)
                    }
                }
            }
        }
    }

    private var writers: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.l) {
                SectionTitle("What wrote the most")
                if runner.rates.isEmpty {
                    Text(runner.tier >= 2 ? "Nothing wrote enough to measure." : "Needs Developer Mode on the iPhone to see.")
                        .font(.callout).foregroundStyle(VColor.ink2)
                } else {
                    let top = runner.rates.map { $0.bytesWrittenPerMinute / 1e6 }.max() ?? 1
                    ForEach(runner.rates) { r in
                        ValueBar(raw: r.process, value: r.bytesWrittenPerMinute / 1e6, maxValue: top,
                                 valueText: Plain.megabytesPerMinute(r.bytesWrittenPerMinute / 1e6))
                    }
                }
                Warnings()
                ResultButtons()
            }
        }
    }

    private var busiest: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.l) {
                SectionTitle("Busiest right now")
                let procs = runner.topProcesses
                if procs.isEmpty {
                    Text(runner.tier >= 2 ? "Waiting for the first reading…" : "Needs Developer Mode on the iPhone to see.")
                        .font(.callout).foregroundStyle(VColor.ink2)
                } else {
                    let top = max(100, procs.map(\.cpu).max() ?? 100)
                    ForEach(procs) { p in
                        ValueBar(raw: p.name, value: p.cpu, maxValue: top, valueText: "\(Int(p.cpu.rounded()))% of a core",
                                 color: p.cpu >= 50 ? VColor.attention : VColor.fine)
                    }
                }
            }
        }
    }
}

private struct TemperatureFigure: View {
    var celsius: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Battery temperature")
            if let c = celsius {
                let h = Plain.heat(c)
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Text(c, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .foregroundStyle(VColor.ink)
                        .contentTransition(.numericText(value: c))
                    Text("°C").font(.title2).foregroundStyle(VColor.ink2)
                    Text(h.word).font(.callout.weight(.semibold)).foregroundStyle(VColor.heatText(h.level))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(VColor.heat(h.level).opacity(0.18)))
                }
                .animation(Motion.settle, value: c)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Battery temperature")
                .accessibilityValue("\(String(format: "%.1f", c)) degrees Celsius, \(h.word)")
            } else {
                Text("—").font(.system(size: 52, weight: .semibold, design: .rounded)).foregroundStyle(VColor.ink2)
                    .accessibilityHidden(true)
                Text("This iPhone does not report battery temperature to a Mac.").font(.caption).foregroundStyle(VColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BatteryFigure: View {
    var level: Double?
    var charging: Bool?
    var watts: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Battery")
            if let l = level {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Int((l * 100).rounded()), format: .number)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .foregroundStyle(VColor.ink)
                        .contentTransition(.numericText(value: l))
                    Text("%").font(.title2).foregroundStyle(VColor.ink2)
                }
                .animation(Motion.settle, value: l)
            } else {
                Text("—").font(.system(size: 52, weight: .semibold, design: .rounded)).foregroundStyle(VColor.ink2)
            }
            Label(chargeText, systemImage: charging == true ? "bolt.fill" : "battery.75percent")
                .font(.callout).foregroundStyle(VColor.ink2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue("\(level.map { "\(Int(($0 * 100).rounded())) percent" } ?? "unknown"), \(chargeText)")
    }
    private var chargeText: String {
        switch charging {
        case true?: (watts ?? 0) > 0 ? "Charging at \(Int(watts!)) W" : "Charging"
        case false?: "On battery"
        case nil: "Charging unknown"
        }
    }
}

private struct TemperatureChart: View {
    var points: [EngineRunner.TempPoint]
    var body: some View {
        let lo = (points.map(\.c).min() ?? 30) - 0.5, hi = (points.map(\.c).max() ?? 35) + 0.5
        Chart(points) { p in
            AreaMark(x: .value("Time", p.t), yStart: .value("Base", lo), yEnd: .value("°C", p.c))
                .foregroundStyle(LinearGradient(colors: [VColor.heat(.serious).opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", p.t), y: .value("°C", p.c))
                .foregroundStyle(VColor.heat(.serious))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                // Short watches need seconds, or every label reads the same minute.
                AxisValueLabel(format: span < 600 ? .dateTime.hour().minute().second() : .dateTime.hour().minute())
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery temperature chart")
        .accessibilityValue(summary)
    }
    private var span: TimeInterval { (points.last?.t ?? .now).timeIntervalSince(points.first?.t ?? .now) }

    private var summary: String {
        guard let first = points.first, let last = points.last else { return "No readings" }
        let peak = points.map(\.c).max() ?? last.c
        return String(format: "From %.1f to %.1f degrees, peak %.1f, over %@", first.c, last.c, peak, Plain.duration(last.t.timeIntervalSince(first.t)))
    }
}

// MARK: - Test a fix

struct FixStage: View {
    @Environment(EngineRunner.self) private var runner
    @State private var action = FixAction.restart
    @State private var minutes = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            switch runner.phase {
            case .ready:
                StageTitle(title: "Test a fix", subtitle: "Vitals measures what is writing, you make one change on the iPhone, then it measures again and compares.")
                Card {
                    VStack(alignment: .leading, spacing: Space.l) {
                        Text("What will you change?").font(.headline).foregroundStyle(VColor.ink)
                        VStack(spacing: Space.s) {
                            ForEach(FixAction.allCases) { a in
                                FixChoice(action: a, selected: action == a) { action = a }
                            }
                        }
                        Text("Each measurement").font(.headline).foregroundStyle(VColor.ink)
                        Picker("Each measurement", selection: $minutes) {
                            Text("3 minutes").tag(3.0); Text("5 minutes").tag(5.0); Text("10 minutes").tag(10.0)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        .accessibilityLabel("Each measurement")
                        Text(runner.simulate ? "Simulated iPhone: each measurement takes 20 seconds." : "About \(Int(minutes * 2 + 2)) minutes in all, with a minute for the iPhone to settle after the change.")
                            .font(.caption).foregroundStyle(VColor.ink2)
                        Button("Start") { runner.startFixTest(action: action.title, windowMinutes: minutes) }
                            .vitalsButton(.primary, size: .regular).keyboardShortcut(.defaultAction)
                    }
                }
            case .failed(let why):
                FixHeader(step: 0)
                FailedView(title: "The test stopped", why: why) { runner.open(.fix) }
            case .finished:
                FixHeader(step: 3)
                FixResult()
            case .yourTurn:
                FixHeader(step: 1)
                YourTurn(action: FixAction(title: runner.fixAction) ?? .restart)
            case .settling:
                FixHeader(step: 2)
                Card { PhaseProgress(start: runner.phaseStart, length: runner.phaseLength, label: "Letting the iPhone settle before measuring again") }
            case .after:
                FixHeader(step: 2)
                Card { PhaseProgress(start: runner.phaseStart, length: runner.phaseLength, label: "Measuring after") }
            case .working:
                FixHeader(step: 0)
                Card {
                    VStack(alignment: .leading, spacing: Space.m) {
                        PhaseProgress(start: runner.phaseStart, length: runner.phaseLength, label: "Measuring before")
                        Text("Leave the iPhone as it is. Vitals will tell you when it is your turn.").font(.callout).foregroundStyle(VColor.ink2)
                    }
                }
            }
        }
    }
}

enum FixAction: String, CaseIterable, Identifiable {
    case restart, icloud, charger
    var id: String { rawValue }
    var title: String {
        switch self {
        case .restart: "Restart the phone"
        case .icloud: "Turn iCloud Drive off and on"
        case .charger: "Plug in or unplug the charger"
        }
    }
    var detail: String {
        switch self {
        case .restart: "Stops stuck background work. The iPhone leaves USB for a minute; Wi-Fi is used if it does not come back."
        case .icloud: "Settings > [your name] > iCloud > iCloud Drive. Turn it off, wait ten seconds, turn it on."
        case .charger: "Shows how much charging changes heat and activity."
        }
    }
    var steps: [String] {
        switch self {
        case .restart: ["Press and release volume up, then volume down.", "Hold the side button, slide to power off.", "Wait 30 seconds, then hold the side button until the Apple logo appears.", "Unlock the iPhone."]
        case .icloud: ["Open Settings > [your name] > iCloud > iCloud Drive.", "Turn Sync this iPhone off, wait ten seconds, turn it on."]
        case .charger: ["Plug the charger in, or unplug it if it was in."]
        }
    }
    init?(title: String?) { guard let f = Self.allCases.first(where: { $0.title == title }) else { return nil }; self = f }
}

private struct FixChoice: View {
    var action: FixAction
    var selected: Bool
    var choose: () -> Void
    var body: some View {
        Button(action: choose) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? VColor.ink : VColor.ink2).font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title).font(.body.weight(.medium)).foregroundStyle(VColor.ink)
                    Text(action.detail).font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? VColor.ink.opacity(0.08) : VColor.ground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(action.detail)
    }
}

private struct FixHeader: View {
    @Environment(EngineRunner.self) private var runner
    var step: Int
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            StageTitle(title: "Test a fix", subtitle: runner.fixAction)
            StepTrack(current: step)
        }
    }
}

/// The one moment the person acts. Big, unmissable, with the steps for the chosen change.
private struct YourTurn: View {
    @Environment(EngineRunner.self) private var runner
    var action: FixAction
    @Environment(\.motionLevel) private var motion
    @State private var appeared = false

    var body: some View {
        Card(tint: VColor.ink) {
            VStack(alignment: .leading, spacing: Space.l) {
                Label("Your turn", systemImage: "hand.point.right.fill")
                    .font(.headline).foregroundStyle(VColor.ink)
                Text(action.title).font(.system(.title, weight: .bold)).foregroundStyle(VColor.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Array(action.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text("\(i + 1)").font(VFont.numeral(.body, weight: .semibold)).foregroundStyle(VColor.ink)
                            Text(s).font(.body).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Take your time. Vitals waits.").font(.callout).foregroundStyle(VColor.ink2)
                Button("It's back") { runner.actionDone() }
                    .vitalsButton(.primary, size: .regular)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Tells Vitals the change is done, so it can measure again")
            }
        }
        .scaleEffect(appeared || motion == .still ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(Motion.change(motion, Motion.settle)) { appeared = true } }
    }
}

private struct FixResult: View {
    @Environment(EngineRunner.self) private var runner
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let v = runner.plainVerdict {
                Text(v).font(.title2.weight(.semibold)).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Card {
                VStack(alignment: .leading, spacing: Space.l) {
                    SectionTitle("Writing to storage, before and after")
                    if runner.comparison.isEmpty {
                        Text("Nothing wrote more than 1 MB a minute before or after.").font(.callout).foregroundStyle(VColor.ink2)
                    } else {
                        let top = runner.comparison.map { max($0.beforeMBPerMinute ?? 0, $0.afterMBPerMinute ?? 0) }.max() ?? 1
                        ForEach(runner.comparison.prefix(6)) { r in BeforeAfterBar(row: r, maxValue: top) }
                    }
                    Warnings()
                    HStack(spacing: Space.m) {
                        Button("Show in Finder") { runner.showInFinder() }.vitalsButton(.secondary, size: .regular)
                        Button("Test again") { runner.open(.fix) }.vitalsButton(.secondary, size: .regular)
                        Spacer()
                        Button("Done") { runner.goHome() }.vitalsButton(.primary, size: .regular).keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
    }
}

// MARK: - Shared result parts

private struct ResultButtons: View {
    @Environment(EngineRunner.self) private var runner
    var body: some View {
        HStack(spacing: Space.m) {
            Button { runner.airDrop() } label: { Label("AirDrop to iPhone", systemImage: "square.and.arrow.up") }
                .vitalsButton(.primary, size: .regular)
                .help("Send to your iPhone, then open it in Vitals")
            Button("Show in Finder") { runner.showInFinder() }.vitalsButton(.secondary, size: .regular)
            Spacer()
            Button("Done") { runner.goHome() }.vitalsButton(.secondary, size: .regular)
        }
    }
}

private struct Warnings: View {
    @Environment(EngineRunner.self) private var runner
    var body: some View {
        ForEach(runner.warnings, id: \.self) { w in
            Label(w.prefix(1).uppercased() + w.dropFirst(), systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(VColor.attention).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FailedView: View {
    var title: String
    var why: String
    var retry: () -> Void
    @Environment(EngineRunner.self) private var runner
    var body: some View {
        Card(tint: VColor.problem) {
            VStack(alignment: .leading, spacing: Space.m) {
                Label(title, systemImage: "exclamationmark.octagon").font(.title3.weight(.semibold)).foregroundStyle(VColor.problem)
                Text(why).font(.callout).foregroundStyle(VColor.ink).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Check the cable and that the iPhone is unlocked, or turn on Wi-Fi on the left, then try again.")
                    .font(.callout).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Try again", action: retry).vitalsButton(.primary, size: .regular)
                    Button("All tasks") { runner.goHome() }.vitalsButton(.secondary, size: .regular)
                }
            }
        }
    }
}

extension Plain {
    /// "Documents › Vitals › Logs 2026-11-15 12.50" rather than a full path.
    static func savedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var p = url.path
        if p.hasPrefix(home) { p = String(p.dropFirst(home.count + 1)) }
        return p.split(separator: "/").joined(separator: " › ")
    }
}

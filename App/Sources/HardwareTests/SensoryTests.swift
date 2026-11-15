import SwiftUI
import AVFoundation
import CoreHaptics
import VitalsKit
import VitalsDesign

// MARK: Touch

/// "Tests as play": paint every cell of a grid; each new cell fills and taps a light haptic.
struct TouchTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var showGrid = false

    var body: some View {
        TestPage(kind: .touch, details: $details, suggested: $suggested) {
            Button("Start painting") { showGrid = true }.vitalsButton(.primary)
            Text("The grid fills the whole screen. Close it with the button in the middle when you are done or stuck.")
                .font(.subheadline).foregroundStyle(VColor.ink2)
        }
        .fullScreenCover(isPresented: $showGrid) {
            TouchGridView { grid in
                details = ["\(grid.painted.count) of \(grid.total) cells painted"]
                suggested = grid.complete ? .passed : .failed
                showGrid = false
            }
        }
    }
}

struct TouchGridView: View {
    var done: (TouchGrid) -> Void
    @State private var grid = TouchGrid(columns: 8, rows: 14)
    @State private var ticks = 0
    @State private var last: CGPoint?
    @Environment(\.motionLevel) private var motion

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / CGFloat(grid.columns), ch = geo.size.height / CGFloat(grid.rows)
            ZStack {
                VColor.ground
                ForEach(0..<grid.rows, id: \.self) { r in
                    ForEach(0..<grid.columns, id: \.self) { c in
                        let on = grid.isPainted(column: c, row: r)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(on ? VColor.fine.opacity(0.55 + 0.35 * Double((c + r) % 3) / 2) : VColor.ink2.opacity(0.08))
                            .scaleEffect(on ? 1 : 0.86)
                            .animation(motion == .full ? Motion.snappy : nil, value: on)
                            .frame(width: cw - 2, height: ch - 2)
                            .position(x: (CGFloat(c) + 0.5) * cw, y: (CGFloat(r) + 0.5) * ch)
                    }
                }
                VStack(spacing: 6) {
                    Text("\(grid.painted.count) / \(grid.total)").font(VFont.numeral(.title2)).foregroundStyle(VColor.ink)
                    Button(grid.complete ? "Done" : "Finish") { done(grid) }.vitalsButton(.primary)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let from = last ?? v.location
                    if grid.paintLine(from: (from.x, from.y), to: (v.location.x, v.location.y), width: geo.size.width, height: geo.size.height) > 0 { ticks += 1 }
                    last = v.location
                }
                .onEnded { _ in last = nil })
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: ticks)
        .onChange(of: grid.complete) { _, complete in if complete { done(grid) } }
        .accessibilityElement()
        .accessibilityLabel("Touch grid, \(grid.painted.count) of \(grid.total) cells painted")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction(named: grid.complete ? "Done" : "Finish") { done(grid) }
        .accessibilityAction(.escape) { done(grid) }
    }
}

// MARK: Display

struct DisplayTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var showing = false

    var body: some View {
        TestPage(kind: .display, details: $details, suggested: $suggested) {
            Button("Show test colours") { showing = true }.vitalsButton(.primary)
            Text("Tap to step through black, white, red, green, blue and grey, then a brightness sweep. Look for dots that stay one colour.")
                .font(.subheadline).foregroundStyle(VColor.ink2)
        }
        .fullScreenCover(isPresented: $showing) {
            ColourSequence { details = ["Showed 6 solid colours and a brightness sweep"]; showing = false }
        }
    }
}

struct ColourSequence: View {
    var done: () -> Void
    @State private var step = 0
    @State private var sweep = 0.0
    @Environment(\.motionLevel) private var motion
    let colours: [Color] = [.black, .white, Color(.sRGB, red: 1, green: 0, blue: 0), Color(.sRGB, red: 0, green: 1, blue: 0), Color(.sRGB, red: 0, green: 0, blue: 1), Color(white: 0.5)]

    var body: some View {
        ZStack {
            if step < colours.count {
                colours[step]
            } else {
                // Brightness sweep: a grey ramp that walks from black to white. Under Reduce Motion it is a still ramp.
                LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
                    .overlay(Color.white.opacity(motion == .full ? sweep : 0))
                    .onAppear { if motion == .full { withAnimation(.linear(duration: 3).repeatCount(2, autoreverses: true)) { sweep = 1 } } }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { if step >= colours.count { done() } else { step += 1 } }
        .accessibilityElement()
        .accessibilityAction(.escape) { done() }
        .accessibilityLabel(step < colours.count ? "Test colour \(step + 1) of \(colours.count). Tap for the next." : "Brightness sweep. Tap to finish.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: Speakers

@MainActor
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()

    /// `receiver` routes to the earpiece (play-and-record without speaker override); otherwise the loudspeakers.
    func play(pan: Float, receiver: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if receiver {
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.overrideOutputAudioPort(.none)
        } else {
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let samples = ToneGenerator.samples(frequency: receiver ? 600 : 880, seconds: 1.2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        if engine.attachedNodes.contains(node) == false {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        node.pan = pan
        try engine.start()
        node.scheduleBuffer(buffer, at: nil)
        node.play()
    }

    func stop() {
        node.stop(); engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// "Speaker test shows sound travelling": rings travel out from the speaker being tested.
struct SpeakerTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var player: TonePlayer?
    @State private var playing: String?
    @State private var heard: [String: Bool] = [:]
    @State private var error: String?

    let outputs: [(id: String, title: String, pan: Float, receiver: Bool)] = [
        ("bottom", "Bottom speaker", -1, false), ("top", "Top speaker", 1, false), ("earpiece", "Earpiece", 0, true),
    ]

    var body: some View {
        TestPage(kind: .speakers, details: $details, suggested: $suggested) {
            ForEach(outputs, id: \.id) { o in
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) {
                        AdaptiveRow {
                            HStack {
                                SoundRings(active: playing == o.id).frame(width: 54, height: 54)
                                Text(o.title).font(.headline)
                            }
                        } trailing: {
                            Button("Play") { play(o) }.vitalsButton(.secondary).accessibilityLabel("Play tone, \(o.title)")
                        }
                        AdaptiveRow {
                            Text("Heard it?").font(.subheadline).foregroundStyle(VColor.ink2)
                        } trailing: {
                            VerdictButtons(subject: o.title, yes: "Heard", no: "Not heard", value: heard[o.id]) { mark(o.id, $0) }
                        }
                    }
                }
            }
            Text("Top and bottom are the stereo pair; hold the phone in landscape to hear them separately. Which physical speaker plays each side is decided by iOS.")
                .font(.caption).foregroundStyle(VColor.ink2)
            if let error { Text(error).font(.caption).foregroundStyle(VColor.attention) }
        }
        .onDisappear { player?.stop() }
    }

    func play(_ o: (id: String, title: String, pan: Float, receiver: Bool)) {
        if player == nil { player = TonePlayer() }
        do {
            try player?.play(pan: o.pan, receiver: o.receiver)
            playing = o.id
            Task { try? await Task.sleep(for: .seconds(1.3)); if playing == o.id { playing = nil } }
        } catch { self.error = "Could not play: \(error.localizedDescription)" }
    }

    func mark(_ id: String, _ yes: Bool) {
        heard[id] = yes
        details = outputs.compactMap { o in heard[o.id].map { "\(o.title): \($0 ? "heard" : "not heard")" } }
        if heard.count == outputs.count { suggested = heard.values.allSatisfy { $0 } ? .passed : .failed }
    }
}

struct SoundRings: View {
    var active: Bool
    @Environment(\.motionLevel) private var motion
    var body: some View {
        TimelineView(.animation(paused: !(active && motion.allowsContinuous))) { ctx in
            Canvas { g, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                g.fill(Circle().path(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(active ? VColor.fine : VColor.ink2))
                guard active else { return }
                let t = ctx.date.timeIntervalSinceReferenceDate
                for i in 0..<3 {
                    let p = motion.allowsContinuous ? (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : Double(i + 1) / 3
                    let r = 6 + p * (size.width / 2 - 6)
                    g.stroke(Circle().path(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(VColor.fine.opacity(1 - p)), lineWidth: 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Microphones

@MainActor
@Observable
final class MicTester {
    struct Mic: Identifiable { let id: String; let name: String; let source: AVAudioSessionDataSourceDescription? }
    var mics: [Mic] = []
    var level: Float = 0
    var recording: String?
    var playing: String?
    var peaks: [String: Float] = [:]
    var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var meterTask: Task<Void, Never>?
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("vitals-mic-test.m4a")

    func load() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { error = "Microphone access was not allowed. Settings > Privacy & Security > Microphone."; return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try? s.setActive(true)
        let builtIn = s.availableInputs?.first { $0.portType == .builtInMic }
        let sources = builtIn?.dataSources ?? []
        mics = sources.isEmpty ? [Mic(id: "default", name: "Built-in microphone", source: nil)]
            : sources.map { Mic(id: $0.dataSourceName, name: "\($0.dataSourceName) microphone", source: $0) }
    }

    func record(_ mic: Mic) {
        let s = AVAudioSession.sharedInstance()
        if let src = mic.source, let port = s.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try? port.setPreferredDataSource(src)
            try? s.setPreferredInput(port)
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.record(forDuration: 3)
            recording = mic.id
            peaks[mic.id] = -160
            meterTask = Task { [weak self] in
                for _ in 0..<32 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, let r = self.recorder else { return }
                    r.updateMeters()
                    self.level = r.averagePower(forChannel: 0)
                    self.peaks[mic.id] = max(self.peaks[mic.id] ?? -160, r.peakPower(forChannel: 0))
                }
                self?.recording = nil
                self?.playBack(mic.id)
            }
        } catch { self.error = error.localizedDescription }
    }

    func playBack(_ id: String) {
        player = try? AVAudioPlayer(contentsOf: url)
        playing = id
        player?.play()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            self?.playing = nil
            // Nothing is kept: the recording is deleted as soon as it has played.
            if let u = self?.url { try? FileManager.default.removeItem(at: u) }
        }
    }

    func stop() {
        meterTask?.cancel(); recorder?.stop(); player?.stop()
        try? FileManager.default.removeItem(at: url)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct MicrophoneTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var tester = MicTester()
    @State private var heard: [String: Bool] = [:]

    var body: some View {
        TestPage(kind: .microphones, details: $details, suggested: $suggested) {
            if let e = tester.error { UnavailableNote(text: e) }
            ForEach(tester.mics) { mic in
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) {
                        AdaptiveRow {
                            Text(mic.name).font(.headline)
                        } trailing: {
                            Button(tester.recording == mic.id ? "Recording…" : tester.playing == mic.id ? "Playing…" : "Record 3 s") { tester.record(mic) }
                                .vitalsButton(.secondary).disabled(tester.recording != nil || tester.playing != nil)
                                .accessibilityHint("Records \(mic.name) for 3 seconds, then plays it back")
                        }
                        LevelMeter(db: tester.recording == mic.id ? tester.level : (tester.peaks[mic.id] ?? -160))
                            .frame(height: 10)
                        if let p = tester.peaks[mic.id], tester.recording == nil {
                            AdaptiveRow {
                                Text("Peak \(Int(p)) dBFS · heard the playback?").font(.caption).foregroundStyle(VColor.ink2)
                            } trailing: {
                                VerdictButtons(subject: mic.name, yes: "Clear", no: "Not heard", value: heard[mic.id]) { mark(mic, $0) }
                            }
                        }
                    }
                }
            }
            if tester.mics.isEmpty && tester.error == nil { ProgressView() }
        }
        .task { await tester.load() }
        .onDisappear { tester.stop() }
    }

    func mark(_ mic: MicTester.Mic, _ yes: Bool) {
        heard[mic.id] = yes
        details = tester.mics.compactMap { m in heard[m.id].map { "\(m.name): \($0 ? "clear" : "not heard"), peak \(Int(tester.peaks[m.id] ?? -160)) dBFS" } }
        if heard.count == tester.mics.count { suggested = heard.values.allSatisfy { $0 } ? .passed : .failed }
    }
}

struct LevelMeter: View {
    var db: Float
    var body: some View {
        GeometryReader { g in
            let f = CGFloat(max(0, min(1, (db + 60) / 60)))
            ZStack(alignment: .leading) {
                Capsule().fill(VColor.ink2.opacity(0.15))
                Capsule().fill(f > 0.9 ? VColor.attention : VColor.fine).frame(width: g.size.width * f)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(db <= -159 ? "silent" : "\(Int(db)) decibels")
    }
}

// MARK: Haptics

struct HapticsTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var felt: [String: Bool] = [:]
    @State private var engine: CHHapticEngine?
    let patterns = ["Single tap", "Double tap", "Ramp", "Long buzz"]

    var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    var body: some View {
        TestPage(kind: .haptics, details: $details, suggested: $suggested) {
            if !supported {
                UnavailableNote(text: "This device reports no haptics hardware (the Simulator never has it).")
            }
            ForEach(patterns, id: \.self) { p in
                Panel {
                    AdaptiveRow {
                        Text(p).font(.headline)
                    } trailing: {
                        HStack {
                            Button("Play") { play(p) }.vitalsButton(.secondary).disabled(!supported).accessibilityLabel("Play \(p)")
                            VerdictButtons(subject: p, yes: "Felt", no: "Not felt", value: felt[p]) { mark(p, $0) }
                        }
                    }
                }
            }
        }
        .onAppear {
            details = ["Haptics hardware: \(supported ? "reported" : "not reported")"]
            if !supported { suggested = .unavailable }
        }
    }

    func play(_ name: String) {
        do {
            if engine == nil { engine = try CHHapticEngine(); try engine?.start() }
            func tap(_ t: TimeInterval, _ i: Float = 1) -> CHHapticEvent {
                CHHapticEvent(eventType: .hapticTransient, parameters: [.init(parameterID: .hapticIntensity, value: i), .init(parameterID: .hapticSharpness, value: 0.6)], relativeTime: t)
            }
            let events: [CHHapticEvent]
            switch name {
            case "Double tap": events = [tap(0), tap(0.15)]
            case "Ramp": events = (0..<8).map { tap(Double($0) * 0.08, Float($0 + 1) / 8) }
            case "Long buzz": events = [CHHapticEvent(eventType: .hapticContinuous, parameters: [.init(parameterID: .hapticIntensity, value: 0.8)], relativeTime: 0, duration: 0.8)]
            default: events = [tap(0)]
            }
            try engine?.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: 0)
        } catch { details.append("Error: \(error.localizedDescription)") }
    }

    func mark(_ p: String, _ yes: Bool) {
        felt[p] = yes
        details = ["Haptics hardware: \(supported ? "reported" : "not reported")"] + patterns.compactMap { n in felt[n].map { "\(n): \($0 ? "felt" : "not felt")" } }
        if felt.count == patterns.count { suggested = felt.values.allSatisfy { $0 } ? .passed : .failed }
    }
}

// MARK: Flashlight

struct FlashlightTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var on = false

    var device: AVCaptureDevice? { AVCaptureDevice.default(for: .video) }

    var body: some View {
        TestPage(kind: .flashlight, details: $details, suggested: $suggested) {
            if device?.hasTorch == true {
                Toggle("Flashlight", isOn: $on).font(.headline).tint(VColor.ink)
                    .onChange(of: on) { _, v in set(v) }
            } else {
                UnavailableNote(text: "No flashlight found on this device (the Simulator has none).")
            }
        }
        .onAppear {
            details = ["Torch: \(device?.hasTorch == true ? "present" : "not found")"]
            if device?.hasTorch != true { suggested = .unavailable }
        }
        .onDisappear { set(false) }
    }

    func set(_ v: Bool) {
        guard let d = device, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = v ? .on : .off
        d.unlockForConfiguration()
    }
}

import SwiftUI
import CoreMotion
import LocalAuthentication
import AVFoundation
import AVKit
import VitalsKit
import VitalsDesign

// MARK: Motion sensors

@MainActor
@Observable
final class MotionReader {
    let manager = CMMotionManager()
    let altimeter = CMAltimeter()
    var accel = (x: 0.0, y: 0.0, z: 0.0)
    var gyro = (x: 0.0, y: 0.0, z: 0.0)
    var mag = (x: 0.0, y: 0.0, z: 0.0)
    var pressure: Double?
    var activity: [String: SignalActivity] = [
        "Accelerometer": SignalActivity(threshold: 0.15), "Gyroscope": SignalActivity(threshold: 0.3),
        "Magnetometer": SignalActivity(threshold: 3), "Barometer": SignalActivity(threshold: 0.001),
    ]

    var available: [String: Bool] {
        ["Accelerometer": manager.isAccelerometerAvailable, "Gyroscope": manager.isGyroAvailable,
         "Magnetometer": manager.isMagnetometerAvailable, "Barometer": CMAltimeter.isRelativeAltitudeAvailable()]
    }

    func start() {
        manager.accelerometerUpdateInterval = 0.05
        manager.gyroUpdateInterval = 0.05
        manager.magnetometerUpdateInterval = 0.1
        manager.startAccelerometerUpdates(to: .main) { [weak self] d, _ in
            guard let a = d?.acceleration else { return }
            MainActor.assumeIsolated { self?.accel = (a.x, a.y, a.z); self?.activity["Accelerometer"]?.add(a.x + a.y + a.z) }
        }
        manager.startGyroUpdates(to: .main) { [weak self] d, _ in
            guard let r = d?.rotationRate else { return }
            MainActor.assumeIsolated { self?.gyro = (r.x, r.y, r.z); self?.activity["Gyroscope"]?.add(r.x + r.y + r.z) }
        }
        manager.startMagnetometerUpdates(to: .main) { [weak self] d, _ in
            guard let m = d?.magneticField else { return }
            MainActor.assumeIsolated { self?.mag = (m.x, m.y, m.z); self?.activity["Magnetometer"]?.add(m.x + m.y + m.z) }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] d, _ in
                guard let p = d?.pressure.doubleValue else { return }
                MainActor.assumeIsolated { self?.pressure = p; self?.activity["Barometer"]?.add(p) }
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates(); manager.stopGyroUpdates(); manager.stopMagnetometerUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
}

struct MotionTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var reader = MotionReader()

    var body: some View {
        TestPage(kind: .motion, details: $details, suggested: $suggested) {
            sensor("Accelerometer", "g", [reader.accel.x, reader.accel.y, reader.accel.z])
            sensor("Gyroscope", "rad/s", [reader.gyro.x, reader.gyro.y, reader.gyro.z])
            sensor("Magnetometer", "µT", [reader.mag.x, reader.mag.y, reader.mag.z])
            sensor("Barometer", "kPa", reader.pressure.map { [$0] } ?? [])
        }
        .onAppear { reader.start() }
        .onDisappear { reader.stop() }
        .onChange(of: reader.activity.values.map(\.everLive)) { _, _ in update() }
        .task { try? await Task.sleep(for: .seconds(1)); update() }
    }

    func sensor(_ name: String, _ unit: String, _ values: [Double]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(.headline)
                    Spacer()
                    let live = reader.activity[name]?.everLive == true
                    if reader.available[name] == false {
                        Text("Not available").font(.subheadline).foregroundStyle(VColor.ink2)
                    } else {
                        StatusMark(live ? .good : .unknown, size: 10)
                        Text(live ? "Responding" : "Move the phone").font(.subheadline).foregroundStyle(live ? VColor.fine : VColor.ink2)
                    }
                }
                Text(values.isEmpty ? "—" : values.map { $0.formatted(.number.precision(.fractionLength(3))) }.joined(separator: "  ") + " \(unit)")
                    .font(VFont.mono).foregroundStyle(VColor.ink)
            }
        }
        .accessibilityElement(children: .combine)
    }

    func update() {
        details = reader.available.keys.sorted().map { k in
            reader.available[k] == false ? "\(k): not available" : "\(k): \(reader.activity[k]?.everLive == true ? "responding" : "no change seen")"
        }
        let present = reader.available.filter(\.value).keys
        if present.isEmpty { suggested = .unavailable }
        else if present.allSatisfy({ reader.activity[$0]?.everLive == true }) { suggested = .passed }
    }
}

// MARK: Proximity

struct ProximityTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var near = false
    @State private var changes = 0
    @State private var supported = true

    var body: some View {
        TestPage(kind: .proximity, details: $details, suggested: $suggested) {
            if !supported {
                UnavailableNote(text: "This device does not report a proximity sensor (the Simulator has none).")
            } else {
                Panel {
                    HStack {
                        Circle().fill(near ? VColor.fine : VColor.ink2.opacity(0.25)).frame(width: 28, height: 28)
                        Text(near ? "Covered: the screen turned off" : "Not covered").font(.headline)
                        Spacer()
                        Text("\(changes) changes").font(.subheadline).foregroundStyle(VColor.ink2)
                    }
                }
            }
        }
        .onAppear {
            UIDevice.current.isProximityMonitoringEnabled = true
            supported = UIDevice.current.isProximityMonitoringEnabled
            if !supported { suggested = .unavailable; details = ["Proximity monitoring: not supported"] }
        }
        .onDisappear { UIDevice.current.isProximityMonitoringEnabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.proximityStateDidChangeNotification)) { _ in
            near = UIDevice.current.proximityState
            changes += 1
            details = ["Proximity state changed \(changes) times"]
            if changes >= 2 { suggested = .passed }
        }
    }
}

// MARK: Face ID

struct FaceIDTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var running = false

    var body: some View {
        TestPage(kind: .faceID, details: $details, suggested: $suggested) {
            Button(running ? "Waiting for Face ID…" : "Start Face ID") { Task { await run() } }
                .vitalsButton(.primary).disabled(running)
            Text("Vitals only learns whether Face ID recognised you. It never sees face data.").font(.caption).foregroundStyle(VColor.ink2)
        }
    }

    func run() async {
        running = true
        defer { running = false }
        let ctx = LAContext()
        var error: NSError?
        let can = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let type: String = switch ctx.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "none"
        }
        guard can else {
            details = ["Biometry: \(type)", "Not available: \(error?.localizedDescription ?? "unknown")"]
            suggested = ctx.biometryType == .none ? .unavailable : .failed
            return
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Check that Face ID recognises you")
            details = ["Biometry: \(type)", ok ? "Recognised" : "Not recognised"]
            suggested = ok ? .passed : .failed
        } catch {
            details = ["Biometry: \(type)", "Ended: \(error.localizedDescription)"]
            suggested = (error as? LAError)?.code == .userCancel ? nil : .failed
        }
    }
}

// MARK: Buttons

/// Volume buttons: seen through `AVAudioSession.outputVolume` changes (public KVO).
/// Camera Control: seen through `AVCaptureEventInteraction` while a capture session runs (public, iOS 17.2+).
/// Action button: apps cannot observe it, unless the person assigns it to Vitals' "Run check-up" shortcut,
/// in which case pressing it reaches Vitals through the shared intent flag.
@MainActor
@Observable
final class ButtonWatcher {
    var volumeUp = false
    var volumeDown = false
    var cameraControl = false
    var actionButton = false
    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = AVAudioSession.sharedInstance().outputVolume
    let session = AVCaptureSession()
    var cameraAvailable = false

    func start() {
        try? AVAudioSession.sharedInstance().setActive(true)
        lastVolume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor in
                guard let self else { return }
                if v > self.lastVolume { self.volumeUp = true } else if v < self.lastVolume { self.volumeDown = true }
                self.lastVolume = v
            }
        }
        // A capture session must run for Camera Control (and capture-event volume presses) to reach the app.
        if let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
            session.addInput(input)
            cameraAvailable = true
            nonisolated(unsafe) let s = session  // AVCaptureSession is thread-safe for start/stop; Apple recommends a background queue
            Task.detached { s.startRunning() }
        }
        SharedContainer.defaults.removeObject(forKey: PendingAction.scanKey)
    }

    func checkActionButton() {
        if SharedContainer.defaults.object(forKey: PendingAction.scanKey) != nil {
            actionButton = true
            SharedContainer.defaults.removeObject(forKey: PendingAction.scanKey)
        }
    }

    func stop() {
        observation?.invalidate()
        nonisolated(unsafe) let s = session  // AVCaptureSession is thread-safe for start/stop; Apple recommends a background queue
        Task.detached { s.stopRunning() }
    }
}

struct ButtonsTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var watcher = ButtonWatcher()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TestPage(kind: .buttons, details: $details, suggested: $suggested) {
            Panel {
                VStack(alignment: .leading, spacing: Space.m) {
                    row("Volume up", watcher.volumeUp)
                    row("Volume down", watcher.volumeDown)
                    row("Camera Control", watcher.cameraControl, note: watcher.cameraAvailable ? "Press it once" : "No camera session (Simulator)")
                    row("Action button", watcher.actionButton, note: "Only if it is set to Vitals' Run check-up")
                }
            }
            Text("iOS does not tell apps about the side button. The Action button reaches Vitals only through a shortcut you assign in Settings > Action Button.")
                .font(.caption).foregroundStyle(VColor.ink2)
        }
        .background { CaptureEventCatcher { watcher.cameraControl = true; update() } }
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
        .onChange(of: phase) { _, p in if p == .active { watcher.checkActionButton(); update() } }
        .onChange(of: watcher.volumeUp) { _, _ in update() }
        .onChange(of: watcher.volumeDown) { _, _ in update() }
    }

    func row(_ title: String, _ seen: Bool, note: String? = nil) -> some View {
        HStack {
            StatusMark(seen ? .good : .unknown, size: 11)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                if let note { Text(note).font(.caption).foregroundStyle(VColor.ink2) }
            }
            Spacer()
            Text(seen ? "Seen" : "Waiting").font(.subheadline).foregroundStyle(seen ? VColor.fine : VColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    func update() {
        details = ["Volume up: \(watcher.volumeUp ? "seen" : "not seen")", "Volume down: \(watcher.volumeDown ? "seen" : "not seen")",
                   "Camera Control: \(watcher.cameraControl ? "seen" : "not seen")", "Action button: \(watcher.actionButton ? "seen" : "not tested")"]
        if watcher.volumeUp && watcher.volumeDown { suggested = .passed }
    }
}

/// Hosts an `AVCaptureEventInteraction` to receive Camera Control presses.
struct CaptureEventCatcher: UIViewRepresentable {
    var onPress: () -> Void
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        // The handler is delivered on the main thread; the view's closure only touches main-actor state.
        nonisolated(unsafe) let handler = onPress
        let interaction = AVCaptureEventInteraction { event in
            if event.phase == .began { handler() }
        }
        v.addInteraction(interaction)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

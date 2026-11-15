import SwiftUI
import AVFoundation
import VitalsKit
import VitalsDesign

// MARK: Cameras

/// Previews each built-in lens and takes one photo that is shown and then discarded (never saved).
@MainActor
@Observable
final class CameraRig: NSObject, AVCapturePhotoCaptureDelegate {
    struct Lens: Identifiable, Hashable { let id: String; let name: String; let device: AVCaptureDevice }
    var lenses: [Lens] = []
    var current: Lens?
    var lastPhoto: UIImage?
    var denied = false
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()

    func load() async {
        let ok = await AVCaptureDevice.requestAccess(for: .video)
        guard ok else { denied = true; return }
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        lenses = found.map { d in
            let side = d.position == .front ? "Front" : "Back"
            return Lens(id: d.uniqueID, name: "\(side) \(d.localizedName.replacingOccurrences(of: "\(side) ", with: ""))", device: d)
        }
        if let first = lenses.first { select(first) }
    }

    func select(_ lens: Lens) {
        current = lens
        lastPhoto = nil
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if let input = try? AVCaptureDeviceInput(device: lens.device), session.canAddInput(input) { session.addInput(input) }
        if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        nonisolated(unsafe) let s = session  // AVCaptureSession is thread-safe for start/stop; Apple recommends a background queue
        if !s.isRunning { Task.detached { s.startRunning() } }
    }

    func capture() { output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self) }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        MainActor.assumeIsolated {
            // Held in memory for this screen only; never written to disk or the photo library.
            lastPhoto = data.flatMap(UIImage.init(data:))
        }
    }

    func stop() { nonisolated(unsafe) let s = session; Task.detached { s.stopRunning() } }
}

struct PreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

struct CameraTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var rig = CameraRig()
    @State private var verdicts: [String: Bool] = [:]

    var body: some View {
        TestPage(kind: .cameras, details: $details, suggested: $suggested) {
            if rig.denied {
                UnavailableNote(text: "Camera access was not allowed. Settings > Privacy & Security > Camera.")
            } else if rig.lenses.isEmpty {
                UnavailableNote(text: "No cameras found (the Simulator has none).")
            } else {
                Picker("Lens", selection: Binding(get: { rig.current }, set: { if let l = $0 { rig.select(l) } })) {
                    ForEach(rig.lenses) { Text($0.name).tag(Optional($0)) }
                }
                .pickerStyle(.menu).tint(VColor.ink)
                ZStack(alignment: .bottomTrailing) {
                    PreviewLayerView(session: rig.session)
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: Space.corner, style: .continuous))
                    if let p = rig.lastPhoto {
                        Image(uiImage: p).resizable().scaledToFill().frame(width: 90, height: 120).clipShape(RoundedRectangle(cornerRadius: 12)).padding(10)
                            .accessibilityLabel("Test photo, not saved")
                    }
                }
                AdaptiveRow {
                    Button("Take test photo") { rig.capture() }.vitalsButton(.secondary)
                } trailing: {
                    if let c = rig.current {
                        VerdictButtons(subject: c.name, yes: "Sharp", no: "Problem", value: verdicts[c.id]) { mark(c, $0) }
                    }
                }
            }
        }
        .task { await rig.load(); details = ["Lenses found: \(rig.lenses.count)"]; if rig.lenses.isEmpty && !rig.denied { suggested = .unavailable } }
        .onDisappear { rig.stop() }
    }

    func mark(_ lens: CameraRig.Lens, _ ok: Bool) {
        verdicts[lens.id] = ok
        details = ["Lenses found: \(rig.lenses.count)"] + rig.lenses.compactMap { l in verdicts[l.id].map { "\(l.name): \($0 ? "sharp" : "problem")" } }
        if verdicts.count == rig.lenses.count { suggested = verdicts.values.allSatisfy { $0 } ? .passed : .failed }
    }
}

// MARK: iPhone Duo

/// Both displays: a pattern that shows edges and corners; the person checks it closed (outer) and open (inner).
/// The hinge reading tells Vitals which display is in use, where iOS provides it.
struct DuoDisplaysTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var outerOK: Bool?
    @State private var innerOK: Bool?
    @Environment(\.hinge) private var hinge

    var body: some View {
        TestPage(kind: .duoDisplays, details: $details, suggested: $suggested) {
            DisplayPattern().frame(height: 260).clipShape(RoundedRectangle(cornerRadius: Space.corner))
            Text("Hinge now: \(hinge.map { "\($0.status.rawValue)\($0.angle.map { ", \(Int($0))°" } ?? "")" } ?? "not reported")")
                .font(.subheadline).foregroundStyle(VColor.ink2)
            Panel {
                VStack(alignment: .leading, spacing: Space.m) {
                    verdictRow("Outer display (closed)", $outerOK)
                    verdictRow("Inner display (open)", $innerOK)
                }
            }
        }
        .onChange(of: outerOK) { _, _ in update() }
        .onChange(of: innerOK) { _, _ in update() }
    }

    func verdictRow(_ title: String, _ value: Binding<Bool?>) -> some View {
        AdaptiveRow {
            Text(title).font(.headline)
        } trailing: {
            VerdictButtons(subject: title, yes: "Looks right", no: "Problem", value: value.wrappedValue) { value.wrappedValue = $0 }
        }
    }

    func update() {
        details = [outerOK.map { "Outer: \($0 ? "looks right" : "problem")" }, innerOK.map { "Inner: \($0 ? "looks right" : "problem")" }].compactMap { $0 }
        if let o = outerOK, let i = innerOK { suggested = o && i ? .passed : .failed }
    }
}

struct DisplayPattern: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let step: CGFloat = 24
            var x: CGFloat = 0
            while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.35))); x += step }
            var y: CGFloat = 0
            while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.35))); y += step }
            ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)), with: .color(.white), lineWidth: 4)
            let colours: [Color] = [.red, .green, .blue, .white]
            for (i, c) in colours.enumerated() {
                let w = size.width / 4
                ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: size.height / 2 - 20, width: w, height: 40)), with: .color(c))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Display test pattern: grid, white border and colour bars")
    }
}

/// Hinge: watch the reported status and angle while folding.
struct HingeTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var seen = Set<String>()
    @State private var minAngle: Double?
    @State private var maxAngle: Double?
    @Environment(\.hinge) private var hinge

    var body: some View {
        TestPage(kind: .hinge, details: $details, suggested: $suggested) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    if let h = hinge {
                        BigValue(h.angle.map { "\(Int($0))" } ?? "—", unit: "°", caption: "Hinge: \(h.status.rawValue)")
                    } else {
                        Text("iOS is not reporting a hinge here.").font(.headline)
                    }
                    Text("States seen: \(seen.sorted().joined(separator: ", "))").font(.subheadline).foregroundStyle(VColor.ink2)
                    Text("Read from SwiftUI onHingeChange (iOS 27.1). Apple says angle updates are throttled and not precise.").font(.caption).foregroundStyle(VColor.ink2)
                }
            }
        }
        .onChange(of: hinge) { _, h in
            guard let h else { return }
            seen.insert(h.status.rawValue)
            if let a = h.angle { minAngle = min(minAngle ?? a, a); maxAngle = max(maxAngle ?? a, a) }
            details = ["States: \(seen.sorted().joined(separator: ", "))", "Angle range: \(minAngle.map { "\(Int($0))" } ?? "—")° to \(maxAngle.map { "\(Int($0))" } ?? "—")°"]
            if seen.contains("closed") && seen.contains("fullyOpen") { suggested = .passed }
        }
        .onAppear {
            if let h = hinge { seen.insert(h.status.rawValue) } else { details = ["Hinge: not reported"]; suggested = .unavailable }
        }
    }
}

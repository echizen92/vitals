import SwiftUI
import VitalsKit
import VitalsDesign

/// "I dropped my phone": press Start once and Vitals runs the check-up (battery, heat, storage, memory,
/// network, software), then walks every hardware test in the order a drop most often damages things.
/// Each test is the same screen as in Tests and can be skipped. The summary uses this run's results only,
/// and they go into the report like any other test.
struct DropCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionLevel) private var motion

    private enum Stage: Equatable { case intro, checkup, test(Int), summary }
    @State private var stage: Stage = .intro
    @State private var startedAt = Date.now

    private var plan: [HardwareTestKind] { DropCheck.plan(isDuo: model.isDuo) }

    var body: some View {
        SwiftUI.Group {
            switch stage {
            case .intro: intro.transition(stageTransition)
            case .checkup: checkupStep.transition(stageTransition)
            case .test(let i): testStep(i).transition(stageTransition)
            case .summary: summary.transition(stageTransition)
            }
        }
        .vitalsGround()
        .animation(Motion.change(motion, Motion.settle), value: stage)
        .navigationTitle(stage == .intro || stage == .summary ? "Drop check" : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isRunning)
        .toolbar(isRunning ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            if isRunning {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End") { stage = .summary }
                        .accessibilityHint("Stops the check and shows what was found so far.")
                }
            }
        }
    }

    /// Steps slide in from the trailing edge like pages; under Reduce Motion they cross-fade.
    private var stageTransition: AnyTransition {
        motion == .still ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                   removal: .move(edge: .leading).combined(with: .opacity))
    }

    private var isRunning: Bool {
        if case .test = stage { return true }
        return stage == .checkup
    }

    // MARK: Intro

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                DropHero()
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text("Dropped your phone?").font(.largeTitle.bold()).foregroundStyle(VColor.ink)
                Text("One check goes through everything a drop can damage: the screen and touch, cameras, speakers and microphones, buttons, Face ID, sensors and radios. Vitals reads the battery, heat and storage on its own first.")
                    .font(.body).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.s) {
                    Label("\(plan.count) checks, about 5 minutes", systemImage: "clock")
                    Label("Each one tells you what to do; skip any you like", systemImage: "forward")
                    Label("Nothing from the camera or microphone is kept", systemImage: "lock")
                }
                .font(.subheadline).foregroundStyle(VColor.ink)
                Button { start() } label: { Text("Start").frame(maxWidth: .infinity) }
                    .vitalsButton(.primary)
                    .padding(.top, Space.s)
                Text("A check cannot see inside the phone. If it is bent, swollen, hot or smells of burning, stop using it and get it looked at.")
                    .font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    private func start() {
        startedAt = .now
        stage = .checkup
        Task {
            await model.runCheckup()
            if stage == .checkup { stage = plan.isEmpty ? .summary : .test(0) }
        }
    }

    // MARK: Running

    private var checkupStep: some View {
        VStack(spacing: Space.l) {
            progress(step: 0, title: "Check-up")
            Spacer()
            ScanningPhone()
                .accessibilityHidden(true)
            Text("Reading battery, heat, storage, memory, network and software…")
                .font(.headline).foregroundStyle(VColor.ink).multilineTextAlignment(.center)
            Text("No need to touch anything.").font(.subheadline).foregroundStyle(VColor.ink2)
            Spacer()
        }
        .padding(Space.l)
    }

    private func testStep(_ i: Int) -> some View {
        let kind = plan[i]
        return VStack(spacing: 0) {
            progress(step: i + 1, title: "").padding(.horizontal, Space.l).padding(.top, Space.s)
            HardwareTestView(kind: kind)
                .id(kind)   // fresh state for every test
                .environment(\.testRunAdvance) { advance(from: i) }
        }
    }

    private func advance(from i: Int) {
        stage = i + 1 < plan.count ? .test(i + 1) : .summary
    }

    /// "Step 3 of 16 · Cameras" with a bar. Step 0 is the automatic check-up.
    private func progress(step: Int, title: String) -> some View {
        let total = plan.count + 1
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text("Step \(step + 1) of \(total)").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2).monospacedDigit()
                Spacer()
                if !title.isEmpty { Text(title).font(.caption.weight(.semibold)).foregroundStyle(VColor.ink) }
            }
            ProgressView(value: Double(step), total: Double(total)).tint(VColor.ink)
                .animation(Motion.change(motion, Motion.gentle), value: step)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? "Step \(step + 1) of \(total)" : "Step \(step + 1) of \(total), \(title)")
    }

    // MARK: Summary

    private var summary: some View {
        let s = DropCheck.summarize(plan: plan, results: model.hardwareResults, since: startedAt)
        let checkupIssues = (model.checkup?.takenAt ?? .distantPast) >= startedAt
            ? (model.checkup?.results.filter { $0.status == .problem || $0.status == .attention } ?? []) : []
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                verdictHeader(s).appearIn(order: 0)
                if !s.failed.isEmpty {
                    resultList("Needs a look", s.failed, .problem).appearIn(order: 1)
                    Panel {
                        Text("A failed check after a drop usually means a repair. Apple, or an Apple Authorised Service Provider, can confirm it; the Vitals report shows them what failed and when.")
                            .font(.subheadline).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !checkupIssues.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionTitle("From the check-up")
                        ForEach(checkupIssues) { r in
                            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                                StatusMark(r.status, size: 11)
                                Text(r.sentence).font(.subheadline).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !s.notChecked.isEmpty { resultList("Not checked", s.notChecked, .unknown).appearIn(order: 2) }
                if !s.passed.isEmpty { resultList("Working", s.passed, .good).appearIn(order: 3) }
                VStack(spacing: Space.m) {
                    Button { model.showReport = true; model.tab = .checkup } label: { Text("Open the report").frame(maxWidth: .infinity) }
                        .vitalsButton(.primary)
                    Button { start() } label: { Text("Run the drop check again").frame(maxWidth: .infinity) }
                        .vitalsButton(.secondary)
                }
                .padding(.top, Space.s)
            }
            .padding(Space.l)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func verdictHeader(_ s: DropCheck.Summary) -> some View {
        let (status, title, line): (Status, String, String) = switch s.verdict {
        case .damageFound:
            (.problem, "\(s.failed.count) \(s.failed.count == 1 ? "part needs" : "parts need") a look",
             "These did not pass after the drop.")
        case .allPassed:
            (.good, "No damage found", "Every check passed. Vitals cannot see inside the phone, so watch for heat, swelling or new faults.")
        case .passedWithGaps:
            (.good, "No damage found in \(s.passed.count) checks",
             "\(s.notChecked.count) \(s.notChecked.count == 1 ? "was" : "were") not checked; you can run \(s.notChecked.count == 1 ? "it" : "them") below.")
        case .notChecked:
            (.unknown, "Nothing was checked", "Start again when you have a few minutes.")
        }
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                VerdictMark(status: status)
                Text(title).font(VFont.title).foregroundStyle(VColor.ink)
            }
            Text(line).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func resultList(_ title: String, _ kinds: [HardwareTestKind], _ status: Status) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionTitle(title)
            ForEach(kinds) { k in
                NavigationLink { HardwareTestView(kind: k) } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: k.symbol).frame(width: 28).foregroundStyle(VColor.ink2).accessibilityHidden(true)
                        Text(k.title).foregroundStyle(VColor.ink)
                        Spacer()
                        StatusMark(status, size: 11)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2).accessibilityHidden(true)
                    }
                    .padding(.vertical, Space.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(status == .good ? "Opens the test" : "Runs this test now")
            }
        }
    }
}

// MARK: Motion

/// The intro: a phone falls, lands with a little squash and a ring where it hits, bounces once and rests; then
/// the brand pulse runs across it, as if the check-up were reading it. Loops slowly. Still under Reduce Motion.
private struct DropHero: View {
    @Environment(\.motionLevel) private var motion

    fileprivate struct Pose { var y: CGFloat = -70; var squash: CGFloat = 1; var tilt: Double = -14; var ring: CGFloat = 0; var pulse: CGFloat = 0 }

    var body: some View {
        if motion == .still {
            HeroPhone(p: Pose(y: 0, squash: 1, tilt: 0, ring: 0, pulse: 1))
        } else {
            HeroPhone(p: Pose())
                .hidden()
                .overlay {
                    // keyframeAnimator drives every property on one clock, so the landing, ring and pulse line up.
                    Color.clear.keyframeAnimator(initialValue: Pose(), repeating: true) { _, p in HeroPhone(p: p) } keyframes: { _ in
                        KeyframeTrack(\.y) {
                            CubicKeyframe(-70, duration: 0.3)
                            CubicKeyframe(0, duration: 0.42)                          // fall (ease in)
                            SpringKeyframe(-12, duration: 0.22, spring: .snappy)       // bounce
                            SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                            LinearKeyframe(0, duration: 1.9)
                            CubicKeyframe(-70, duration: 0.01)
                        }
                        KeyframeTrack(\.squash) {
                            LinearKeyframe(1, duration: 0.72)
                            CubicKeyframe(0.86, duration: 0.07)                       // squash on impact
                            SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                            LinearKeyframe(1, duration: 2.0)
                        }
                        KeyframeTrack(\.tilt) {
                            LinearKeyframe(-14, duration: 0.3)
                            CubicKeyframe(4, duration: 0.42)
                            SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                            LinearKeyframe(0, duration: 1.93)
                        }
                        KeyframeTrack(\.ring) {
                            LinearKeyframe(0, duration: 0.72)
                            LinearKeyframe(0.01, duration: 0.01)
                            CubicKeyframe(1, duration: 0.6)
                            LinearKeyframe(0, duration: 1.82)
                        }
                        KeyframeTrack(\.pulse) {
                            LinearKeyframe(0, duration: 1.3)
                            CubicKeyframe(1, duration: 0.8)                           // pulse sweeps across
                            LinearKeyframe(1, duration: 0.9)
                            LinearKeyframe(0, duration: 0.15)
                        }
                    }
                }
        }
    }
}

private struct HeroPhone: View {
    let p: DropHero.Pose
    var body: some View {
        ZStack(alignment: .bottom) {
            // Impact ring on the "floor"
            Ellipse()
                .stroke(VColor.attention.opacity(p.ring > 0 ? Double(1 - p.ring) * 0.8 : 0), lineWidth: 2)
                .frame(width: 40 + 90 * p.ring, height: 8 + 18 * p.ring)
                .offset(y: 6)
            ZStack {
                RoundedRectangle(cornerRadius: 12).strokeBorder(VColor.ink, lineWidth: 4)
                    .frame(width: 46, height: 80)
                PulseLine()
                    .trim(from: 0, to: p.pulse)
                    .stroke(VColor.fine, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 70, height: 26)
            }
            .rotationEffect(.degrees(p.tilt), anchor: .bottom)
            .scaleEffect(x: 2 - p.squash, y: p.squash, anchor: .bottom)
            .offset(y: p.y)
        }
        .frame(width: 140, height: 120, alignment: .bottom)
    }
}

/// The icon's heartbeat line, in a unit rect.
private struct PulseLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.midY
        p.move(to: CGPoint(x: r.minX, y: y))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: y))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.47, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.56, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.63, y: y))
        p.addLine(to: CGPoint(x: r.maxX, y: y))
        return p
    }
}

/// While the check-up reads the phone: a light sweeps down a phone outline, as on the Check-up screen.
private struct ScanningPhone: View {
    @Environment(\.motionLevel) private var motion
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).strokeBorder(VColor.ink, lineWidth: 4).frame(width: 76, height: 132)
            if motion.allowsContinuous {
                TimelineView(.animation(minimumInterval: motion.frameInterval)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    let y = (0.5 - 0.5 * cos(t * 2 * .pi)) * 110 - 55
                    Capsule().fill(VColor.fine).frame(width: 60, height: 3)
                        .shadow(color: VColor.fine.opacity(0.7), radius: 6)
                        .offset(y: y)
                }
                .frame(width: 76, height: 132)
            } else {
                ProgressView()
            }
        }
    }
}

/// The verdict's status mark pops in once with a bounce.
private struct VerdictMark: View {
    var status: Status
    @Environment(\.motionLevel) private var motion
    @State private var shown = false
    var body: some View {
        StatusMark(status, size: 18)
            .scaleEffect(shown || motion == .still ? 1 : 0.2)
            .opacity(shown || motion == .still ? 1 : 0)
            .onAppear { withAnimation(Motion.change(motion, .spring(duration: 0.5, bounce: 0.45)).delay(0.15)) { shown = true } }
    }
}

/// Summary sections rise in one after another.
private struct AppearIn: ViewModifier {
    var order: Int
    @Environment(\.motionLevel) private var motion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || motion == .still ? 0 : 14)
            .onAppear {
                withAnimation(Motion.change(motion, Motion.settle).delay(motion == .still ? 0 : 0.12 + 0.09 * Double(order))) { shown = true }
            }
    }
}

private extension View {
    func appearIn(order: Int) -> some View { modifier(AppearIn(order: order)) }
}

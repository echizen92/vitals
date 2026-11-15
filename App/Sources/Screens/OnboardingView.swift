import SwiftUI
import VitalsKit
import VitalsDesign

/// First launch. Show, don't tell: the phone model scanning itself, the provenance tags that make every
/// value honest, and the one Settings path that makes logs exist. Three short pages; the page dots sit
/// above the button, never on the text; in landscape the picture and the words sit side by side.
struct OnboardingView: View {
    var done: () -> Void
    @State private var page = 0
    @Environment(\.motionLevel) private var motion
    @Environment(\.verticalSizeClass) private var vSize

    private let pages = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPage(title: "A check-up for this phone",
                               text: "Vitals reads heat, battery, storage, memory, network and software, and lights each part as it checks it.") {
                    OnboardingScanDemo()
                }
                .tag(0)
                OnboardingPage(title: "Honest, and it stays here",
                               text: "No account, no analytics, no server. Every value says where it came from.") {
                    ProvenanceVisual()
                }
                .tag(1)
                OnboardingPage(title: "Let iOS keep a diary",
                               text: "Which app heated the phone lives only in a daily system file. Turn this on and iOS writes one you can share into Vitals. Apple receives it too; turn it off any time.") {
                    SettingsPathVisual()
                }
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: Space.l) {
                PageDots(count: pages, current: page)
                Spacer()
                if page < pages - 1 {
                    Button("Skip") { done() }.foregroundStyle(VColor.ink2)
                }
                Button(page < pages - 1 ? "Next" : "Start") {
                    if page < pages - 1 { withAnimation(Motion.change(motion)) { page += 1 } } else { done() }
                }
                .vitalsButton(.primary)
                .sensoryFeedback(.selection, trigger: page)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, vSize == .compact ? Space.s : Space.l)
        }
        .vitalsGround()
        .interactiveDismissDisabled()
    }
}

/// Picture and words. Stacked in portrait, side by side when height is short (landscape).
struct OnboardingPage<Visual: View>: View {
    var title: String
    var text: String
    @ViewBuilder var visual: Visual
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let words = VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(VColor.ink).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(text).font(.title3).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
        }
        // Wide space (landscape, or iPhone Duo's inner display): picture and words side by side, centred as one
        // group. Tall space: picture above words.
        GeometryReader { outer in
            if vSize == .compact || outer.size.width > outer.size.height * 1.05 {
                HStack(spacing: Space.xxl) {
                    visual
                        .frame(maxWidth: .infinity, maxHeight: min(outer.size.height * 0.8, 460))
                    ScrollView {
                        words.padding(.vertical, Space.l)
                            .frame(maxWidth: 420, alignment: .leading)
                            .frame(minHeight: outer.size.height, alignment: .center)   // centred when it fits
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Space.xxl)
                .frame(maxWidth: 1100, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        visual
                            .frame(height: typeSize.isAccessibilitySize ? 220 : min(440, outer.size.height * 0.55), alignment: .bottom)
                            .frame(maxWidth: .infinity)
                        words
                    }
                    .padding(Space.xl)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, minHeight: outer.size.height)   // centred when it fits
                }
            }
        }
    }
}

private struct PageDots: View {
    var count: Int
    var current: Int
    @Environment(\.motionLevel) private var motion
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i == current ? VColor.ink : VColor.ink2.opacity(0.3))
                    .frame(width: i == current ? 22 : 8, height: 8)
            }
        }
        .animation(Motion.change(motion, Motion.snappy), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// The phone model checking itself, on a loop: each region lights as its "reading" lands.
/// Under Reduce Motion it shows the finished model, still.
struct OnboardingScanDemo: View {
    @Environment(AppModel.self) private var model
    @Environment(\.motionLevel) private var motion
    @State private var scan = ScanState()
    private let order: [(Area, Status)] = [(.network, .good), (.heat, .attention), (.memory, .good),
                                           (.storage, .good), (.battery, .good), (.software, .good)]

    var body: some View {
        // This phone, as it is: two panels on iPhone Duo (following the hinge), one elsewhere.
        PhoneModelView(scan: scan, results: nil, isDuo: model.isDuo)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.isDuo ? "A drawing of this iPhone Duo, open. Each part lights up as Vitals checks it."
                                            : "A drawing of the phone. Each part lights up as Vitals checks it.")
            .task(id: motion) {
                guard motion.allowsContinuous else {
                    scan = ScanState(phase: .done, finished: Dictionary(uniqueKeysWithValues: order))
                    return
                }
                while !Task.isCancelled {
                    scan = ScanState(phase: .running)
                    try? await Task.sleep(for: .milliseconds(700))
                    for (area, status) in order {
                        try? await Task.sleep(for: .milliseconds(420))
                        scan.finished[area] = status
                    }
                    scan.phase = .done
                    try? await Task.sleep(for: .seconds(3))
                }
            }
    }
}

/// Where values come from, as the tags the app really uses, around a lock.
private struct ProvenanceVisual: View {
    @State private var shown = false
    @Environment(\.motionLevel) private var motion
    var body: some View {
        VStack(spacing: Space.xl) {
            ZStack {
                Circle().fill(VColor.fine.opacity(0.12)).frame(width: 150, height: 150)
                Image(systemName: "lock.iphone").font(.system(size: 64, weight: .light)).foregroundStyle(VColor.ink)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.m) {
                row(.measured, "read from iOS just now", 0)
                row(.parsedFromLog, "from a system file you shared", 1)
                row(.inferred, "worked out by Vitals, and says so", 2)
            }
        }
        .onAppear { withAnimation(Motion.change(motion, Motion.settle)) { shown = true } }
    }
    private func row(_ p: Provenance, _ text: String, _ i: Int) -> some View {
        HStack(spacing: Space.m) {
            ProvenanceTag(p)
            Text(text).font(.subheadline).foregroundStyle(VColor.ink2)
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown || motion == .still ? 0 : 12)
        .animation(Motion.change(motion, Motion.settle.delay(0.12 * Double(i))), value: shown)
        .accessibilityElement(children: .combine)
    }
}

/// The Settings path as a trail of steps, ending at the switch.
private struct SettingsPathVisual: View {
    private let steps = [("gearshape.fill", "Settings"), ("hand.raised.fill", "Privacy & Security"),
                         ("chart.bar.fill", "Analytics & Improvements")]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: Space.m) {
                    Image(systemName: s.0).font(.body).foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(i == 0 ? Color.gray : i == 1 ? Color.blue : Color.indigo))
                    Text(s.1).font(.headline).foregroundStyle(VColor.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(VColor.ink2)
                }
                .padding(.vertical, Space.m)
                if i < steps.count - 1 { Divider() }
            }
            Divider()
            HStack {
                Text("Share iPhone Analytics").font(.headline).foregroundStyle(VColor.ink)
                Spacer()
                Toggle("", isOn: .constant(true)).labelsHidden().tint(.green).allowsHitTesting(false)
            }
            .padding(.vertical, Space.m)
        }
        .padding(.horizontal, Space.l)
        .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous).fill(VColor.surface))
        .frame(maxWidth: 420)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Settings, Privacy and Security, Analytics and Improvements, then turn on Share iPhone Analytics.")
    }
}

import SwiftUI
import VitalsKit
import VitalsDesign

/// Home. Verdict first, detail on demand. A split view, so iPhone Duo's inner display shows the
/// scorecard beside the selected area, and every other iPhone pushes the detail.
struct CheckupScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            CheckupHome(selection: $model.selectedArea)
                .navigationTitle("Check-up")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.showReport = true } label: { Label("Report", systemImage: "doc.richtext") }
                    }
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 460)
        } detail: {
            NavigationStack {
                if let area = model.selectedArea {
                    AreaDetailView(area: area)
                } else {
                    DetailPlaceholder()
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $model.showReport) { ReportScreen() }
        .sheet(isPresented: $model.showGallery) { NavigationStack { WidgetGallery() } }
    }
}

struct CheckupHome: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Area?

    var body: some View {
        List(selection: $selection) {
            Section {
                VerdictHeader()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: Space.l, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            if model.caseRecord?.current.primary != nil {
                Section {
                    CaseCard().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                } header: { SectionTitle("What is going on") }
            }
            Section {
                ForEach(Array(Area.allCases.enumerated()), id: \.element) { i, area in
                    NavigationLink(value: area) {
                        ScorecardRow(area: area, result: model.checkup?.result(for: area), scanStatus: model.scan.finished[area],
                                     scanning: model.scan.phase == .running && model.scan.finished[area] == nil, index: i)
                    }
                    .listRowBackground(VColor.surface)
                }
            } header: {
                SectionTitle("Scorecard")
            } footer: {
                ProvenanceLegend().padding(.top, Space.s)
            }
            Section {
                NavigationLink { ReliefScreen() } label: {
                    ReliefRow(symbol: "bolt.heart", title: "Quick relief", subtitle: "Cool down, save battery, restart or free space now.")
                }
                .listRowBackground(VColor.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .vitalsGround()
        .refreshable { await model.runCheckup() }
    }
}

/// The hero: the phone model, the overall verdict and the one button.
struct VerdictHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Verdict first, and named: the worst area and its own sentence, not a count.
    var verdict: (title: String, detail: String?, status: Status, area: Area?) {
        guard let c = model.checkup else { return ("Ready for a check-up", nil, .unknown, nil) }
        let ranked = c.results.filter { $0.status == .problem || $0.status == .attention }
            .sorted { $0.status > $1.status }
        if let worst = ranked.first {
            let sentence = worst.sentence.hasSuffix(".") ? String(worst.sentence.dropLast()) : worst.sentence
            let more = ranked.count - 1
            return ("\(worst.area.shortTitle): \(sentence)",
                    more > 0 ? "and \(more) more \(more == 1 ? "area" : "areas") to look at" : nil,
                    worst.status, worst.area)
        }
        if let expected = c.results.first(where: { $0.status == .expected }) {
            return ("\(expected.area.shortTitle): \(expected.sentence.hasSuffix(".") ? String(expected.sentence.dropLast()) : expected.sentence)", nil, .expected, expected.area)
        }
        if c.results.allSatisfy({ $0.status == .unknown }) { return ("Not enough data yet", nil, .unknown, nil) }
        return ("All clear", "Every area looks healthy", .good, nil)
    }

    var body: some View {
        VStack(spacing: Space.l) {
            PhoneModelView(scan: model.scan, results: model.checkup, isDuo: model.isDuo,
                           onSelect: model.scan.phase == .running ? nil : { area in model.selectedArea = area })
                .frame(height: typeSize.isAccessibilitySize ? 240 : 360)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(scanAccessibilityLabel)

            VStack(spacing: 6) {
                InjectionBanner()
                if model.scan.phase == .running {
                    Text("Checking \(model.scan.finished.count) of \(Area.allCases.count)")
                        .font(VFont.title).foregroundStyle(VColor.ink)
                        .contentTransition(.numericText())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StatusMark(verdict.status, size: 16)
                        Text(verdict.title).font(VFont.title).foregroundStyle(VColor.ink)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    if let d = verdict.detail { Text(d).font(.subheadline.weight(.medium)).foregroundStyle(VColor.ink2) }
                    if let area = verdict.area {
                        Button { model.selectedArea = area } label: {
                            Label("See why", systemImage: "chevron.right").labelStyle(TrailingIcon())
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VColor.ink)
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens \(area.title)")
                    }
                }
                Text(subtitle).font(.footnote).foregroundStyle(VColor.ink2).multilineTextAlignment(.center)
            }
            .vitalsAnimation(value: model.scan.phase)
            // A tick as each area's reading lands, then success or warning for the verdict.
            .sensoryFeedback(.selection, trigger: model.scan.finished.count) { _, new in new > 0 }
            .sensoryFeedback(trigger: model.scan.phase) { _, new in
                guard new == .done else { return nil }
                return verdict.status == .problem || verdict.status == .attention ? .warning : .success
            }

            Button {
                Task { await model.runCheckup() }
            } label: {
                Text(model.checkup == nil ? "Run check-up" : "Check again")
                    .frame(maxWidth: 320)
            }
            .vitalsButton(.primary)
            .disabled(model.scan.phase == .running)
            .accessibilityHint("Reads every on-device sensor and setting. Takes a few seconds.")
        }
        .padding(.top, Space.s)
    }

    var subtitle: String {
        if model.scan.phase == .running { return "Each part lights up as its reading comes in." }
        guard let c = model.checkup else { return "Reads battery, heat, storage, memory, network and software on this phone. Nothing leaves it." }
        return "Last checked \(c.takenAt.formatted(.relative(presentation: .named)))"
    }

    var scanAccessibilityLabel: String {
        if model.scan.phase == .running { return "Check-up in progress, \(model.scan.finished.count) of \(Area.allCases.count) areas read" }
        return "Phone model, \(verdict.title). Each part opens its area."
    }
}

struct ScorecardRow: View {
    var area: Area
    var result: AreaResult?
    var scanStatus: Status?
    var scanning: Bool
    var index: Int = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.motionLevel) private var motion
    @State private var arrived = false

    var status: Status { scanStatus ?? result?.status ?? .unknown }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Group {
                if scanning {
                    ProgressView().controlSize(.small)
                } else {
                    StatusMark(status, size: 13)
                }
            }
            .frame(width: 18)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }

            VStack(alignment: .leading, spacing: 3) {
                // Title and status side by side; stacked at accessibility sizes so words never break.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
                layout {
                    Text(area.title).font(.headline).foregroundStyle(VColor.ink)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    if !scanning, result != nil || scanStatus != nil {
                        Text(status.label).font(.subheadline.weight(.medium)).foregroundStyle(VColor.status(status))
                    }
                }
                Text(result?.sentence ?? (scanning ? "Reading…" : "Not checked yet."))
                    .font(.subheadline).foregroundStyle(VColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        // Staged arrival: rows settle in one after another the first time they appear; status changes spring.
        .opacity(arrived ? 1 : 0)
        .offset(y: arrived || motion != .full ? 0 : 10)
        .onAppear {
            guard !arrived else { return }
            withAnimation(Motion.change(motion, Motion.settle.delay(0.05 * Double(index)))) { arrived = true }
        }
        .animation(Motion.change(motion, Motion.settle), value: status)
        .animation(Motion.change(motion, Motion.settle), value: scanning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(area.title), \(scanning ? "reading" : status.label). \(result?.sentence ?? "")")
    }
}

struct ProvenanceLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Every value says where it came from:").font(.caption).foregroundStyle(VColor.ink2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ProvenanceTag(.measured); ProvenanceTag(.parsedFromLog); ProvenanceTag(.inferred) }
                VStack(alignment: .leading, spacing: 6) { ProvenanceTag(.measured); ProvenanceTag(.parsedFromLog); ProvenanceTag(.inferred) }
            }
        }
    }
}

struct DetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Choose an area", systemImage: "waveform.path.ecg",
                               description: Text("Pick a row in the scorecard to see its readings and where each came from."))
            .vitalsGround()
    }
}

/// Text first, then the icon ("See why ›").
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.title; configuration.icon.imageScale(.small) }
    }
}

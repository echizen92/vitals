import SwiftUI
import VitalsKit
import VitalsDesign

/// One area: verdict, findings with their evidence, then every raw reading with its provenance.
struct AreaDetailView: View {
    let area: Area
    @Environment(AppModel.self) private var model

    var result: AreaResult? { model.checkup?.result(for: area) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                if let result {
                    if !result.findings.isEmpty {
                        VStack(alignment: .leading, spacing: Space.m) {
                            SectionTitle("Findings")
                            ForEach(result.findings) { FindingCard(finding: $0) }
                        }
                    }
                    AreaExtras(area: area)
                    VStack(alignment: .leading, spacing: Space.m) {
                        SectionTitle("Readings")
                        Panel {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(result.readings.enumerated()), id: \.element.id) { i, r in
                                    if i > 0 { Divider().overlay(VColor.hairline).padding(.vertical, 6) }
                                    ReadingRow(r)
                                }
                            }
                        }
                    }
                    CouldNotDetermine(items: result.couldNotDetermine ?? [])
                    if area == .battery, let shares = model.batteryShares, !shares.apps.isEmpty {
                        VStack(alignment: .leading, spacing: Space.m) {
                            SectionTitle("Battery use by app")
                            Panel { BatterySharesCard(result: shares) }
                        }
                    }
                    Text("Read \(result.readings.first?.takenAt.formatted(date: .abbreviated, time: .standard) ?? "")")
                        .font(.caption).foregroundStyle(VColor.ink2)
                } else {
                    AreaExtras(area: area)
                    ContentUnavailableView("Not checked yet", systemImage: area.symbol,
                                           description: Text("Run a check-up to read this area."))
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            InjectionBanner()
            HStack(spacing: 10) {
                Image(systemName: area.symbol).font(.title2).foregroundStyle(VColor.ink2).accessibilityHidden(true)
                StatusLabel(result?.status ?? .unknown)
            }
            Text(result?.sentence ?? "No reading yet.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(VColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct FindingCard: View {
    let finding: Finding
    @State private var expanded = false

    var status: Status {
        if finding.expected == true { return .expected }
        switch finding.severity { case .problem: return .problem; case .attention: return .attention; case .info: return .unknown }
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if finding.severity == .info && finding.expected != true {
                        Image(systemName: "info.circle").foregroundStyle(VColor.ink2).accessibilityHidden(true)
                    } else {
                        StatusMark(status, size: 12)
                    }
                    Text(finding.summary).font(.headline).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                }
                if let d = finding.detail {
                    Text(d).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                }
                TierLine(finding: finding)
                if !finding.evidence.isEmpty {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(finding.evidence.enumerated()), id: \.offset) { _, e in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(e.text).font(VFont.mono).foregroundStyle(VColor.ink).textSelection(.enabled)
                                    HStack(spacing: 6) {
                                        ProvenanceTag(e.provenance)
                                        if let s = e.source { Text(s).font(.caption2).foregroundStyle(VColor.ink2).lineLimit(2) }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Evidence (\(finding.evidence.count))").font(.subheadline.weight(.medium)).foregroundStyle(VColor.ink)
                    }
                    .tint(VColor.ink)
                }
                AdviceSection(finding: finding)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Area-specific actions: where to get the data Vitals cannot read itself.
struct AreaExtras: View {
    let area: Area
    @Environment(AppModel.self) private var model
    @State private var showScreenshot = false

    var body: some View {
        switch area {
        case .battery where model.batteryHealth?.effectiveMaxCapacity == nil:
            NeedsImportCard(text: "Maximum capacity is not in any public iOS API or log file. Settings > Battery > Battery Health shows it: share a screenshot and Vitals reads it on this phone. The daily analytics file adds the cycle count.",
                            action: "Import a Battery screenshot") { showScreenshot = true }
                .sheet(isPresented: $showScreenshot) { BatteryScreenshotImport() }
        case .heat:
            Button { model.tab = .heat } label: {
                Label("Open the heat timeline", systemImage: "chart.xyaxis.line")
            }
            .vitalsButton(.secondary)
        default:
            EmptyView()
        }
    }
}

struct NeedsImportCard: View {
    var text: String
    var action: String
    var perform: () -> Void
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.m) {
                Label { Text("Needs a log file").font(.headline) } icon: { StatusMark(.unknown, size: 12) }
                    .foregroundStyle(VColor.ink)
                Text(text).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                Button(action: perform) { Text(action) }.vitalsButton(.secondary)
            }
        }
    }
}

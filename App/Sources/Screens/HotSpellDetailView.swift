import SwiftUI
import VitalsKit
import VitalsDesign

/// One hot spell: what Vitals saw, and "Find the cause" from shared logs.
struct HotSpellDetailView: View {
    let spell: HotSpell
    @Environment(AppModel.self) private var model
    @State private var showGuide = false
    @State private var showPicker = false

    var window: (Date, Date) { (spell.start.addingTimeInterval(-2 * 3600), max(spell.end.addingTimeInterval(2 * 3600), spell.start.addingTimeInterval(4 * 3600))) }
    var culprits: [Culprit] { Correlator.culprits(for: spell, events: model.events) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(VColor.heat(spell.peak)).frame(width: 14, height: 14).accessibilityHidden(true)
                        Text("Peak: \(spell.peak.label)").font(.subheadline.weight(.semibold)).foregroundStyle(VColor.heatText(spell.peak))
                    }
                    Text(DayTimeFormatting.string(spell.start)).font(VFont.title).foregroundStyle(VColor.ink)
                    Text(spell.summaryLine).font(.body).foregroundStyle(VColor.ink2)
                    ProvenanceTag(.inferred)
                }
                Panel {
                    let samples = model.samples.filter { $0.hasThermal && $0.takenAt >= window.0 && $0.takenAt <= window.1 }
                    CulpritTimeline(samples: samples, spell: spell, culprits: culprits, from: window.0, to: window.1)
                }
                causeSection
            }
            .padding(Space.l)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle("Hot spell")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGuide) { FourTapsGuide(onChoose: { showGuide = false; showPicker = true }) }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importFiles(at: urls) }
        }
    }

    @ViewBuilder var causeSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionTitle("Find the cause")
            if culprits.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("iOS does not tell apps which process heated the phone. It does write reports when a process uses too much CPU or memory. Share the reports and analytics file from \(spell.start.formatted(date: .abbreviated, time: .omitted)) and Vitals will match them to this spell.")
                            .font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                        Button("Show me how") { showGuide = true }.vitalsButton(.primary)
                    }
                }
            } else {
                ForEach(Array(culprits.prefix(6).enumerated()), id: \.element.id) { i, c in
                    CulpritRow(culprit: c, rank: i + 1)
                }
                Text("Ranked by the reports iOS wrote within 30 minutes of this spell, weighted by kind (CPU over budget counts most) and by how close in time. A report near a hot spell is a lead, not proof.")
                    .font(.caption).foregroundStyle(VColor.ink2)
            }
        }
    }
}

struct CulpritRow: View {
    let culprit: Culprit
    let rank: Int
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(rank)").font(VFont.numeral(.headline)).foregroundStyle(VColor.ink2)
                    ProcessName(raw: culprit.process, rawOnNewLine: true)
                    Spacer()
                    EvidenceBar(value: culprit.score).frame(width: 70, height: 6)
                }
                Text(culprit.summary).font(.subheadline).foregroundStyle(VColor.ink2)
                ForEach(culprit.events.prefix(3)) { e in
                    NavigationLink(value: e) {
                        Text("\(e.timestamp.formatted(date: .omitted, time: .shortened)) \(e.detail ?? e.kind.label)")
                            .font(VFont.mono).foregroundStyle(VColor.ink).lineLimit(3)
                    }
                }
                ProvenanceTag(.parsedFromLog)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lead \(rank): \(ProcessNames.friendly(culprit.process).name). \(culprit.summary). Evidence strength \(Int(culprit.score * 100)) percent of the top lead.")
    }
}

struct EvidenceBar: View {
    var value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(VColor.ink2.opacity(0.18))
                Capsule().fill(LinearGradient(colors: [VColor.heat(.fair), VColor.heat(.critical)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: g.size.width * value)
            }
        }
        .accessibilityHidden(true)
    }
}

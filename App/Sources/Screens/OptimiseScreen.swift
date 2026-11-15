import SwiftUI
import VitalsKit
import VitalsDesign

/// Optimise tab (plan §5.14): relief now, personalised ways to run better, and what you have tried with
/// its measured result.
struct OptimiseScreen: View {
    @Environment(AppModel.self) private var model
    @State private var open: AdviceCatalog.Action?

    var items: [OptimiseItem] {
        OptimiseEngine.items(checkup: model.checkup, samples: model.samples, events: model.events, days: model.analyticsDays,
                             health: model.batteryHealth, benchmark: model.benchmark)
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    NavigationLink { ReliefScreen() } label: {
                        ReliefRow(symbol: "bolt.heart", title: "Quick relief", subtitle: "Cool down, save battery, restart, free space. Each one is measured before and after.")
                    }
                }
                let grouped = Dictionary(grouping: items, by: \.topic)
                if items.isEmpty {
                    Section { Text("Nothing to tune right now. Vitals only suggests things it has evidence for on this phone.").foregroundStyle(VColor.ink2) }
                }
                ForEach(OptimiseItem.Topic.allCases, id: \.self) { topic in
                    if let list = grouped[topic] {
                        Section {
                            ForEach(list) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.headline).foregroundStyle(VColor.ink)
                                    HStack(spacing: 6) {
                                        Text(item.because.text).font(.caption).foregroundStyle(VColor.ink2)
                                        ProvenanceTag(item.because.provenance)
                                    }
                                    ForEach(Array(item.actionIDs.compactMap(AdviceCatalog.action).enumerated()), id: \.element.id) { i, a in
                                        Button { open = a } label: { ActionLine(index: i + 1, action: a) }.buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: { SectionTitle(topic.label) }
                    }
                }
                // Started by the person, not a tip: shown always, below the evidence-based items.
                if let a = AdviceCatalog.action("guided.appPrivacyReport") {
                    Section {
                        Button { open = a } label: {
                            ReliefRow(symbol: "hand.raised", title: a.title, subtitle: "If an app seems to be doing things you did not ask for. iOS's own record, read in Settings.")
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the steps")
                    } header: { SectionTitle("Something feels off?") } footer: {
                        Text(AdviceCatalog.myth("sideChannel") ?? "")
                    }
                }
                if !model.actions.isEmpty {
                    Section {
                        ForEach(model.actions.sorted { $0.doneAt > $1.doneAt }) { a in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(a.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(a.verdict.label).font(.caption.weight(.semibold)).foregroundStyle(a.verdict == .improved ? VColor.fine : VColor.ink2)
                                }
                                Text("\(DayTimeFormatting.string(a.doneAt))\(a.outcomeText.map { " · \($0)" } ?? "")").font(.caption).foregroundStyle(VColor.ink2)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: { SectionTitle("What you tried") } footer: { Text("Included in the report.") }
                }
            }
            .scrollContentBackground(.hidden)
            .vitalsGround()
            .navigationTitle("Optimise")
            .navigationDestination(isPresented: $model.showRelief) { ReliefScreen() }
            .sheet(item: $open) { a in NavigationStack { ActionDetailView(action: a, findingID: nil) } }
            .task { await model.evaluateDueActions() }
        }
    }
}

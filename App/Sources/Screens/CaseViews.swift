import SwiftUI
import VitalsKit
import VitalsDesign

/// The diagnosis as a case on the home screen: the leading hypothesis, its confidence and tier, and the one
/// question Vitals needs answered, if any.
struct CaseCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let record = model.caseRecord, let p = record.current.primary {
            NavigationLink { CaseDetailView() } label: {
                Panel {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack(spacing: 8) {
                            StatusMark(p.status, size: 13)
                            Text(p.title).font(.headline).foregroundStyle(VColor.ink).multilineTextAlignment(.leading)
                        }
                        Text(p.summary).font(.subheadline).foregroundStyle(VColor.ink2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text("\(p.confidence.label) · \(p.tier.label) · \(record.current.state.label)").font(.caption).foregroundStyle(VColor.ink2)
                        }
                        if p.asks != nil {
                            Label("Vitals has one question for you", systemImage: "questionmark.bubble").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the reasoning, history and what to do")
        }
    }
}

struct CaseDetailView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let record = model.caseRecord {
                    Text("State: \(record.current.state.label)").font(.subheadline.weight(.semibold)).foregroundStyle(VColor.ink2)
                    ForEach(record.current.hypotheses) { h in HypothesisCard(h: h) }
                    if !record.history.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s) {
                            SectionTitle("How the verdict changed")
                            ForEach(Array(record.history.enumerated()), id: \.offset) { _, r in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    StatusMark(r.status, size: 10)
                                    Text("\(DayTimeFormatting.string(r.at)): \(r.title) (\(r.confidence.label.lowercased()))").font(.subheadline).foregroundStyle(VColor.ink2)
                                }
                            }
                            Text("Now: \(record.current.primary?.title ?? "nothing open")").font(.subheadline.weight(.semibold))
                        }
                    }
                    CouldNotDetermine(items: record.current.couldNotDetermine)
                } else {
                    ContentUnavailableView("No case yet", systemImage: "stethoscope", description: Text("Share the newest daily analytics file and Vitals will work out what is going on."))
                }
            }
            .padding(Space.l)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle("Diagnosis")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HypothesisCard: View {
    let h: Hypothesis
    @State private var showReasoning = true
    var body: some View {
        let f = DiagnosisEngine.findingForDisplay(h)
        Panel {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StatusMark(h.status, size: 12)
                    Text(h.title).font(.headline).foregroundStyle(VColor.ink)
                }
                Text(h.summary).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                TierLine(finding: f)
                if let next = h.tier.nextTierAdds { Text(next).font(.caption).foregroundStyle(VColor.ink2) }
                if let ask = h.asks { FactQuestion(key: ask) }
                DisclosureGroup(isExpanded: $showReasoning) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(h.reasoning.enumerated()), id: \.offset) { _, e in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.text).font(.subheadline).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                                ProvenanceTag(e.provenance)
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: { Text("Reasoning (\(h.reasoning.count))").font(.subheadline.weight(.medium)).foregroundStyle(VColor.ink) }
                .tint(VColor.ink)
                if let r = h.recheckAfter { Text("Check again after \(DayTimeFormatting.string(r)).").font(.caption).foregroundStyle(VColor.ink2) }
                AdviceSection(finding: f)
            }
        }
    }
}

/// The one fact no file holds (plan §4a item 10). The answer is evidence labelled "You told Vitals".
struct FactQuestion: View {
    let key: UserFact.Key
    @Environment(AppModel.self) private var model
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key.question).font(.subheadline.weight(.semibold)).foregroundStyle(VColor.ink)
            Text(key.help).font(.caption).foregroundStyle(VColor.ink2)
            HStack {
                TextField("About", text: $text).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(maxWidth: 120)
                    .accessibilityLabel("\(key.question) in \(key.unit)")
                Text(key.unit).foregroundStyle(VColor.ink2)
                Button("Use this") { if let v = Double(text.replacingOccurrences(of: ",", with: ".")) { Task { await model.setFact(key, value: v) } } }
                    .vitalsButton(.secondary).disabled(Double(text.replacingOccurrences(of: ",", with: ".")) == nil)
            }
        }
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: 12).fill(VColor.fine.opacity(0.08)))
    }
}

struct CouldNotDetermine: View {
    let items: [String]
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionTitle("Could not determine")
                ForEach(items, id: \.self) { i in
                    Label { Text(i).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true) } icon: { StatusMark(.unknown, size: 10) }
                }
            }
        }
    }
}

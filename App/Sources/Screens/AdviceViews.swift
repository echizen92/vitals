import SwiftUI
import VitalsKit
import VitalsDesign


/// "What to do": one to three actions for a finding, then the escalation ladder (plan §5.14).
struct AdviceSection: View {
    let finding: Finding
    @State private var open: AdviceCatalog.Action?

    var body: some View {
        let actions = AdviceCatalog.actions(for: finding)
        let ladder = AdviceCatalog.escalation(for: finding.resolvedAdviceKey)
        if !actions.isEmpty || AdviceCatalog.safety(for: finding.resolvedAdviceKey) != nil {
            VStack(alignment: .leading, spacing: Space.s) {
                if let safety = AdviceCatalog.safety(for: finding.resolvedAdviceKey), finding.severity == .problem {
                    Label { Text(safety.title + ". " + safety.why).font(.subheadline.weight(.semibold)) } icon: { StatusMark(.problem, size: 12) }
                        .foregroundStyle(VColor.problem)
                }
                Text("What to do").font(.subheadline.weight(.semibold)).foregroundStyle(VColor.ink)
                ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                    Button { open = a } label: { ActionLine(index: i + 1, action: a) }.buttonStyle(.plain)
                }
                if !ladder.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(ladder, id: \.id) { a in
                                Button { open = a } label: {
                                    Label(a.title, systemImage: "arrow.turn.down.right").font(.subheadline).foregroundStyle(VColor.ink)
                                }.buttonStyle(.plain)
                            }
                            Text("Stop trying when these do not help: the report is ready to share with Apple or a repair shop.")
                                .font(.caption).foregroundStyle(VColor.ink2)
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("If that does not help").font(.subheadline.weight(.medium)).foregroundStyle(VColor.ink)
                    }
                    .tint(VColor.ink)
                }
            }
            .padding(.top, Space.s)
            .sheet(item: $open) { a in NavigationStack { ActionDetailView(action: a, findingID: finding.id) } }
        }
    }
}

struct ActionLine: View {
    let index: Int
    let action: AdviceCatalog.Action
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text("\(index)").font(VFont.numeral(.subheadline)).foregroundStyle(VColor.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.subheadline.weight(.medium)).foregroundStyle(VColor.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(action.relief.label).font(.caption2).foregroundStyle(VColor.ink2)
                    if let o = model.outcome(for: action.id) {
                        Text("· \(o.verdict.label)").font(.caption2.weight(.semibold)).foregroundStyle(o.verdict == .improved ? VColor.fine : VColor.ink2)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(VColor.ink2).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the steps")
    }
}

/// One action: why (tied to evidence), numbered steps with the Settings path, effect, downside, source,
/// then "Do it" (Vitals or Shortcuts) or "I did this" (guided/manual), and the measured outcome.
struct ActionDetailView: View {
    let action: AdviceCatalog.Action
    let findingID: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var shortcut: ReliefShortcut? { ReliefShortcut.allCases.first { $0.actionID == action.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Label(action.relief.label, systemImage: "person.crop.circle.badge.checkmark").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2)
                Text(action.why).font(.body).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) {
                        ForEach(Array(action.steps.enumerated()), id: \.offset) { i, s in StepRow(number: i + 1, text: s) }
                    }
                }
                LabeledBlock(title: "What should change", text: action.effect)
                LabeledBlock(title: "Downside", text: action.downside)
                Text("Steps as of \(AdviceCatalog.asOf). Source: \(action.source).").font(.caption).foregroundStyle(VColor.ink2)
                if let o = model.outcome(for: action.id) {
                    Panel {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last time: \(o.verdict.label)").font(.headline)
                            if let t = o.outcomeText { Text(t).font(.subheadline).foregroundStyle(VColor.ink2) }
                            Text(DayTimeFormatting.string(o.doneAt)).font(.caption).foregroundStyle(VColor.ink2)
                        }
                    }
                }
                buttons
            }
            .padding(Space.l)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle(action.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    @ViewBuilder var buttons: some View {
        switch action.relief {
        case .shortcut:
            if let s = shortcut, s.bundledFile != nil {
                Button("Run \(s.rawValue)") { Task { await model.runReliefShortcut(s); dismiss() } }.vitalsButton(.primary)
            } else {
                Text("This shortcut is not in this build yet; follow the steps by hand.").font(.subheadline).foregroundStyle(VColor.ink2)
                markDoneButton
            }
        case .vitals:
            NavigationLink("Open Relief") { ReliefScreen() }.vitalsButton(.primary)
        case .guided, .manual:
            markDoneButton
        }
    }

    var markDoneButton: some View {
        Button {
            Task { await model.markDone(action, finding: findingID); dismiss() }
        } label: {
            Text(action.watch == .none ? "I did this" : "I did this, measure it").frame(maxWidth: .infinity)
        }
        .vitalsButton(.primary)
        .accessibilityHint(action.watch == .none ? "Records the step in your report" : "Vitals compares readings before and after and tells you the result")
    }
}

struct LabeledBlock: View {
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(VColor.ink)
            Text(text).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Tier and confidence for a finding, and what the next tier would add (plan §4c).
struct TierLine: View {
    let finding: Finding
    var body: some View {
        if let tier = finding.tier {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: tier == .phoneOnly ? "iphone" : "laptopcomputer.and.iphone").accessibilityHidden(true)
                    Text("\(tier.label)\(finding.confidence.map { " · \($0.label)" } ?? "")")
                }
                .font(.caption.weight(.medium)).foregroundStyle(VColor.ink2)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

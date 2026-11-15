import SwiftUI
import VitalsKit
import VitalsDesign

/// The frame every hardware test shares: instruction, the test itself, measured details, and a
/// pass / fail / skip choice with notes. Automatic tests suggest an outcome; the person can still change it.
struct TestPage<Content: View>: View {
    let kind: HardwareTestKind
    @Binding var details: [String]
    @Binding var suggested: TestOutcome?
    @ViewBuilder var content: () -> Content

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var saved: TestOutcome?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(kind.instruction).font(.title3).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                content()
                if !details.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(details, id: \.self) { Text($0).font(VFont.mono).foregroundStyle(VColor.ink) }
                            ProvenanceTag(.measured)
                        }
                    }
                }
                if let s = suggested {
                    Label("Vitals suggests: \(s.label)", systemImage: "wand.and.stars").font(.subheadline).foregroundStyle(VColor.ink2)
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(Space.m)
                    .background(RoundedRectangle(cornerRadius: 12).fill(VColor.surface))
                ViewThatFits {
                    HStack(spacing: Space.m) { outcomeButtons }
                    VStack(alignment: .leading, spacing: Space.m) { outcomeButtons }
                }
                Text("Nothing from camera or microphone tests is stored.").font(.caption).foregroundStyle(VColor.ink2)
            }
            .padding(Space.l)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .vitalsGround()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let r = model.hardwareResults.first(where: { $0.kind == kind }) { notes = r.notes }
        }
    }

    @ViewBuilder var outcomeButtons: some View {
        outcome(.passed, "Passed", "checkmark", VColor.fine)
        outcome(.failed, "Failed", "xmark", VColor.problem)
        outcome(.skipped, "Skip", "forward", VColor.ink2)
        if suggested == .unavailable { outcome(.unavailable, "Not available", "minus.circle", VColor.ink2) }
    }

    func outcome(_ o: TestOutcome, _ title: String, _ symbol: String, _ tint: Color) -> some View {
        Button {
            saved = o
            model.saveHardwareResult(HardwareTestResult(kind: kind, outcome: o, notes: notes, details: details))
            dismiss()
        } label: {
            Label(title, systemImage: symbol).frame(minWidth: 90)
        }
        // The result Vitals suggests is the primary action; the others are secondary.
        .vitalsButton(suggested == o ? .primary : .secondary)
        .accessibilityHint(suggested == o ? "Suggested by Vitals" : "")
    }
}

/// A test whose hardware is not on this device or not in the Simulator.
struct UnavailableNote: View {
    var text: String
    var body: some View {
        Panel {
            Label { Text(text).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true) }
                icon: { StatusMark(.unknown, size: 12) }
        }
    }
}

extension TestOutcome {
    var status: Status {
        switch self {
        case .passed: .good
        case .failed: .problem
        case .skipped, .unavailable: .unknown
        }
    }
}

/// A yes/no verdict pair. The chosen one is announced as selected (not shown by tint alone), and each
/// button names its subject so VoiceOver's rotor list is unambiguous ("Heard Earpiece", "Not heard Earpiece").
struct VerdictButtons: View {
    var subject: String
    var yes: String
    var no: String
    var value: Bool?
    var set: (Bool) -> Void

    var body: some View {
        HStack {
            choice(yes, true, VColor.fine)
            choice(no, false, VColor.problem)
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    func choice(_ title: String, _ v: Bool, _ tint: Color) -> some View {
        Button(title) { set(v) }
            .vitalsButton(value == v ? .primary : .secondary, size: .regular)
            .accessibilityLabel("\(title), \(subject)")
            .accessibilityAddTraits(value == v ? .isSelected : [])
    }
}

/// Leading content beside trailing controls; stacks when they do not fit (accessibility text sizes).
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { leading; Spacer(minLength: Space.s); trailing }
            VStack(alignment: .leading, spacing: Space.s) { leading; trailing }
        }
    }
}

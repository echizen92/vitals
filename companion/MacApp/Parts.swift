import SwiftUI
import VitalsKit
import VitalsDesign

// Small building blocks shared by the companion's stages. Colours come from the VitalsDesign tokens,
// which meet 4.5:1 for text on ground and surface in both appearances.

/// A rounded surface card.
struct Card<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous).fill(VColor.surface))
            .overlay {
                if let tint { RoundedRectangle(cornerRadius: Space.corner, style: .continuous).strokeBorder(tint.opacity(0.55), lineWidth: 1.5) }
            }
    }
}

/// A stage's title block: one large line, one plain sentence.
struct StageTitle: View {
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.largeTitle, design: .default, weight: .bold)).foregroundStyle(VColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.title3).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Plain language

enum Plain {
    /// Friendly name first, raw name second, a one-line explanation when the glossary has one.
    static func process(_ raw: String) -> (name: String, raw: String?, what: String?) {
        let short = ProcessGlossary.shortName(raw)
        if let e = ProcessGlossary.entry(for: raw) { return (e.name, short, e.what) }
        return (short, nil, nil)
    }

    /// "iPhone Duo · iOS 27.1" from a product type and version.
    static func device(_ d: [String: String]) -> String? {
        guard let type = d["ProductType"] else { return nil }
        let model = Catalog.modelName(for: type) ?? "iPhone"
        return d["ProductVersion"].map { "\(model) · iOS \($0)" } ?? model
    }

    /// A rough reading of battery temperature in words. Battery, not chip: it lags and runs cooler.
    static func heat(_ c: Double) -> (word: String, level: ThermalLevel) {
        switch c {
        case ..<35: ("Normal", .nominal)
        case ..<40: ("Warm", .fair)
        case ..<45: ("Hot", .serious)
        default: ("Very hot", .critical)
        }
    }

    static func megabytesPerMinute(_ v: Double) -> String {
        v >= 10 ? "\(Int(v.rounded())) MB a minute" : String(format: "%.1f MB a minute", v)
    }

    static func duration(_ s: TimeInterval) -> String {
        let s = max(0, Int(s.rounded()))
        return s >= 60 ? "\(s / 60) min \(String(format: "%02d", s % 60)) s" : "\(s) s"
    }
}

// MARK: - Bars

/// One labelled horizontal bar that settles to its value with the house spring.
struct ValueBar: View {
    var raw: String
    var value: Double
    var maxValue: Double
    var valueText: String
    var color: Color = VColor.ink
    @Environment(\.motionLevel) private var motion

    var body: some View {
        let p = Plain.process(raw)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.name).font(.body.weight(.medium)).foregroundStyle(VColor.ink)
                if let r = p.raw { Text(r).font(.caption).foregroundStyle(VColor.ink2) }
                Spacer()
                Text(valueText).font(VFont.numeral(.body, weight: .medium)).foregroundStyle(VColor.ink)
                    .contentTransition(.numericText(value: value))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(VColor.hairline)
                    Capsule().fill(color).frame(width: max(6, g.size.width * min(1, value / max(maxValue, 0.0001))))
                }
            }
            .frame(height: 8)
        }
        .animation(Motion.change(motion, Motion.settle), value: value)
        .help(p.what ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.name)
        .accessibilityValue(valueText)
        .accessibilityHint(p.what ?? "")
    }
}

/// Before and after for one process: two bars on one row, the change in words.
struct BeforeAfterBar: View {
    var row: CompareRow
    var maxValue: Double
    @Environment(\.motionLevel) private var motion
    @State private var shown = false

    var body: some View {
        let p = Plain.process(row.process)
        let b = row.beforeMBPerMinute ?? 0, a = row.afterMBPerMinute ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.name).font(.body.weight(.medium)).foregroundStyle(VColor.ink)
                if let r = p.raw { Text(r).font(.caption).foregroundStyle(VColor.ink2) }
                Spacer()
                Text(change(b, a)).font(.callout.weight(.semibold)).foregroundStyle(a < b * 0.5 ? VColor.fine : a > b * 2 && a >= 10 ? VColor.attention : VColor.ink2)
            }
            bar(label: "Before", value: b, color: VColor.ink2.opacity(0.55))
            bar(label: "After", value: a, color: VColor.ink)
        }
        .help(p.what ?? "")
        .onAppear { withAnimation(Motion.change(motion, Motion.gentle)) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(p.name)
        .accessibilityValue("Before \(Plain.megabytesPerMinute(b)), after \(Plain.megabytesPerMinute(a)). \(change(b, a))")
    }

    private func change(_ b: Double, _ a: Double) -> String {
        if b >= 1, a < b * 0.5 { return "Down \(Int(((b - a) / b * 100).rounded()))%" }
        if a >= 10, a > max(b, 1) * 2 { return "Up \(String(format: "%.0f", a / max(b, 1)))×" }
        return "About the same"
    }

    private func bar(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: Space.s) {
            Text(label).font(.caption).foregroundStyle(VColor.ink2).frame(width: 44, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(VColor.hairline)
                    Capsule().fill(color).frame(width: max(4, g.size.width * (shown ? min(1, value / max(maxValue, 0.0001)) : 0)))
                }
            }
            .frame(height: 8)
            Text(Plain.megabytesPerMinute(value)).font(VFont.numeral(.caption, weight: .medium)).foregroundStyle(VColor.ink2)
                .frame(width: 120, alignment: .trailing)
        }
    }
}

// MARK: - Progress

/// Time-based progress for the running phase, redrawn once a second (cheap when idle).
struct PhaseProgress: View {
    var start: Date?
    var length: TimeInterval?
    var label: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = start.map { ctx.date.timeIntervalSince($0) } ?? 0
            VStack(alignment: .leading, spacing: 6) {
                if let length, length > 0 {
                    // Drawn here because macOS progress bars ignore the tint.
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(VColor.hairline)
                            Capsule().fill(VColor.ink).frame(width: max(8, g.size.width * min(1, elapsed / length)))
                                .animation(.linear(duration: 1), value: elapsed)
                        }
                    }
                    .frame(height: 8)
                    HStack {
                        Text(label).font(.callout.weight(.medium)).foregroundStyle(VColor.ink)
                        Spacer()
                        Text("\(Plain.duration(length - elapsed)) left").font(VFont.numeral(.callout, weight: .medium)).foregroundStyle(VColor.ink2)
                            .monospacedDigit()
                    }
                } else {
                    ProgressView().progressViewStyle(.linear).tint(VColor.ink)
                    Text(label).font(.callout.weight(.medium)).foregroundStyle(VColor.ink)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(length.map { "\(Plain.duration($0 - elapsed)) left" } ?? "In progress")
        }
    }
}

/// Before, Your turn, After: where a before-and-after test has got to.
struct StepTrack: View {
    var current: Int          // 0 before, 1 your turn, 2 after, 3 done
    @Environment(\.motionLevel) private var motion
    private let steps = ["Before", "Your turn", "After"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: Space.s) {
                    ZStack {
                        Circle().fill(i < current ? VColor.ink : VColor.surface)
                        Circle().strokeBorder(i <= current ? VColor.ink : VColor.hairline, lineWidth: 2)
                        if i < current {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color(light: 0xFFFFFF, dark: 0x0B0F14))
                        } else {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(i == current ? VColor.ink : VColor.ink2)
                        }
                    }
                    .frame(width: 26, height: 26)
                    Text(s).font(.callout.weight(i == current ? .semibold : .regular)).foregroundStyle(i <= current ? VColor.ink : VColor.ink2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(i + 1) of 3, \(s)")
                .accessibilityValue(i < current ? "done" : i == current ? "current" : "to come")
                if i < steps.count - 1 {
                    Rectangle().fill(i < current ? VColor.ink : VColor.hairline).frame(height: 2).frame(maxWidth: .infinity)
                        .padding(.horizontal, Space.m)
                        .accessibilityHidden(true)
                }
            }
        }
        .animation(Motion.change(motion, Motion.settle), value: current)
    }
}

/// A short list row: a symbol and a sentence, for "what this Mac can read" and similar lists.
struct CapabilityRow: View {
    var on: Bool
    var text: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(on ? VColor.fine : VColor.ink2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.callout).foregroundStyle(on ? VColor.ink : VColor.ink2)
                if let note { Text(note).font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "available" : "not available")
    }
}

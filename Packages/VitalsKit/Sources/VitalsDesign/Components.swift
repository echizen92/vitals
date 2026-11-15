import SwiftUI
import VitalsKit

/// Status is always a colour and a shape: circle good, solid ring expected-and-temporary, triangle attention,
/// diamond problem, dashed ring unknown.
public struct StatusMark: View {
    public var status: Status
    public var size: CGFloat
    public init(_ status: Status, size: CGFloat = 14) { self.status = status; self.size = size }

    public var body: some View {
        StatusShape(status: status)
            .fill(status == .unknown || status == .expected ? Color.clear : VColor.status(status))
            .overlay {
                if status == .expected {
                    Circle().strokeBorder(VColor.fine, lineWidth: max(1.8, size / 5))
                }
                if status == .unknown {
                    Circle().strokeBorder(VColor.unknown, style: StrokeStyle(lineWidth: max(1.5, size / 7), dash: [size / 5, size / 6]))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

public struct StatusShape: Shape {
    public var status: Status
    public init(status: Status) { self.status = status }
    public func path(in r: CGRect) -> Path {
        switch status {
        case .good, .unknown, .expected:
            return Circle().path(in: r)
        case .attention:
            var p = Path()
            let inset = r.insetBy(dx: r.width * 0.02, dy: r.height * 0.06)
            p.move(to: CGPoint(x: inset.midX, y: inset.minY))
            p.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
            p.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
            p.closeSubpath()
            return p
        case .problem:
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
            return p
        }
    }
}

/// A status mark with its word, for places where the word fits.
public struct StatusLabel: View {
    public var status: Status
    public init(_ status: Status) { self.status = status }
    public var body: some View {
        HStack(spacing: 6) {
            StatusMark(status, size: 11)
            Text(status.label).font(.subheadline.weight(.semibold)).foregroundStyle(VColor.status(status))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.label)")
    }
}

/// Small tag that says where a value came from. Shown next to every reading.
public struct ProvenanceTag: View {
    public var provenance: Provenance
    public var unverified: Bool
    public init(_ provenance: Provenance, unverified: Bool = false) { self.provenance = provenance; self.unverified = unverified }

    var symbol: String {
        switch provenance {
        case .measured: "gauge.with.needle"
        case .parsedFromLog: "doc.text"
        case .inferred: "function"
        case .userSupplied: "person"
        case .screenshot: "text.viewfinder"
        case .shortcuts: "square.2.layers.3d"
        }
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).imageScale(.small)
            Text(provenance.label)
            if unverified { Text("· unverified") }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(VColor.ink2)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(VColor.ink2.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provenance.label)\(unverified ? ", unverified" : "")")
    }
}

/// A reading with label, value, provenance and source. Reflows to a stack at accessibility sizes.
public struct ReadingRow: View {
    public var reading: Reading
    public var showSource: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(_ reading: Reading, showSource: Bool = true) { self.reading = reading; self.showSource = showSource }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            layout {
                Text(reading.label).font(.body).foregroundStyle(VColor.ink)
                if !typeSize.isAccessibilitySize { Spacer(minLength: Space.m) }
                Text(reading.displayValue).font(VFont.numeral(.body, weight: .semibold)).foregroundStyle(VColor.ink)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            }
            HStack(spacing: 8) {
                ProvenanceTag(reading.provenance, unverified: reading.unverified)
                if showSource {
                    Text(reading.source).font(.caption2).foregroundStyle(VColor.ink2).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The basic container: a soft surface with no border.
public struct Panel<Content: View>: View {
    var content: Content
    var padding: CGFloat
    public init(padding: CGFloat = Space.l, @ViewBuilder content: () -> Content) { self.content = content(); self.padding = padding }
    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Space.corner, style: .continuous).fill(VColor.surface))
    }
}

/// A big number with a caption, the house style for headline values.
public struct BigValue: View {
    public var value: String
    public var unit: String?
    public var caption: String
    public init(_ value: String, unit: String? = nil, caption: String) { self.value = value; self.unit = unit; self.caption = caption }
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(VFont.numeral(.largeTitle))
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(VFont.numeral(.title3, weight: .medium)).foregroundStyle(VColor.ink2) }
            }
            .foregroundStyle(VColor.ink)
            Text(caption).font(.subheadline).foregroundStyle(VColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct SectionTitle: View {
    var text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(.footnote.weight(.semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(VColor.ink2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The three kinds of action, defined once (design decision 2026-11-15). Mint means "fine" and is a status colour,
/// so it is never a button colour.
/// - `primary`: ink fill with a paper label in light, paper fill with an ink label in dark. System Liquid Glass
///   prominent style tinted with ink on iOS/macOS 26 and later, the bordered prominent style before that.
/// - `secondary`: the system glass style (bordered before 26), ink label, same size as primary, so a pair reads as
///   two real controls of different weight.
/// - `tertiary`: plain ink text, medium weight, with a full 44 pt hit area.
/// Destructive actions use `Button(role: .destructive)` with `secondary`; the system colours them.
/// System control size, capsule shape, press behaviour and haptics throughout; labels never wrap.
public enum VitalsButtonKind: Sendable { case primary, secondary, tertiary, destructive }

extension View {
    public func vitalsButton(_ kind: VitalsButtonKind, size: ControlSize = .large) -> some View {
        modifier(VitalsButtonModifier(kind: kind, size: size))
    }
}

private struct VitalsButtonModifier: ViewModifier {
    var kind: VitalsButtonKind
    var size: ControlSize
    #if os(macOS)
    // An inactive Mac window greys the prominent bezel; a forced paper label would vanish on it, so the system
    // chooses the label colour then.
    @Environment(\.appearsActive) private var appearsActive
    #else
    private let appearsActive = true
    #endif
    private var primaryLabel: Color? { appearsActive ? VColor.ground : nil }

    func body(content: Content) -> some View {
        switch kind {
        case .primary:
            styledPrimary(content.lineLimit(1).fontWeight(.semibold))
                .controlSize(size)
                .buttonBorderShape(.capsule)
        case .secondary:
            styledSecondary(content.lineLimit(1).fontWeight(.medium))
                .controlSize(size)
                .buttonBorderShape(.capsule)
        case .destructive:
            // Pair with `Button(role: .destructive)`: the system gives it the problem colour.
            destructive(content.lineLimit(1).fontWeight(.medium))
                .controlSize(size)
                .buttonBorderShape(.capsule)
        case .tertiary:
            content
                .lineLimit(1)
                .fontWeight(.medium)
                .foregroundStyle(VColor.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func styledPrimary(_ v: some View) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            v.foregroundStyle(primaryLabel.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)).buttonStyle(.glassProminent).tint(VColor.ink)
        } else {
            v.foregroundStyle(primaryLabel.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)).buttonStyle(.borderedProminent).tint(VColor.ink)
        }
    }

    @ViewBuilder private func destructive(_ v: some View) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if os(macOS)
            v.buttonStyle(.bordered)
            #else
            v.buttonStyle(.glass)
            #endif
        } else { v.buttonStyle(.bordered) }
    }

    @ViewBuilder private func styledSecondary(_ v: some View) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            #if os(macOS)
            // macOS glass takes the inherited tint (ink) and fills like primary, and clearing the tint hides the
            // label; the standard bordered push button is the Mac's secondary control.
            v.buttonStyle(.bordered)
            #else
            v.foregroundStyle(VColor.ink).buttonStyle(.glass)
            #endif
        } else {
            v.foregroundStyle(VColor.ink).buttonStyle(.bordered).tint(VColor.ink)
        }
    }
}

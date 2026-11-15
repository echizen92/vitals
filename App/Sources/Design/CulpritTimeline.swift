import SwiftUI
import VitalsKit
import VitalsDesign

/// "The reveal": culprit processes rise out of the heat band at the moment their strongest report was
/// written, sized by evidence. Full motion: staggered springs from the band. Reduce Motion / critical heat:
/// they fade in where they belong.
struct CulpritTimeline: View {
    let samples: [Sample]
    let spell: HotSpell
    let culprits: [Culprit]
    let from: Date
    let to: Date

    @Environment(\.motionLevel) private var motion
    @State private var risen = false

    /// Stronger evidence, hotter colour.
    static func heat(for score: Double) -> ThermalLevel {
        score > 0.75 ? .critical : score > 0.5 ? .serious : score > 0.25 ? .fair : .nominal
    }

    /// Approximate width of a caption label, for placing it beside its dot.
    func labelWidth(_ s: String) -> CGFloat { CGFloat(s.count) * 7.2 + 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let bandHeight: CGFloat = 34
                let bandTop = h - bandHeight - 18
                let x = { (d: Date) -> CGFloat in CGFloat(d.timeIntervalSince(from) / to.timeIntervalSince(from)) * w }
                ZStack(alignment: .topLeading) {
                    // Heat band.
                    ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                        let end = i + 1 < samples.count ? min(samples[i + 1].takenAt, s.takenAt.addingTimeInterval(45 * 60)) : s.takenAt.addingTimeInterval(10 * 60)
                        Rectangle().fill(VColor.heat(s.thermal).opacity(s.thermal == .nominal ? 0.55 : 0.95))
                            .frame(width: max(1, x(end) - x(s.takenAt)), height: bandHeight)
                            .position(x: (x(s.takenAt) + x(end)) / 2, y: bandTop + bandHeight / 2)
                    }
                    // Spell bracket.
                    Rectangle().fill(VColor.ink.opacity(0.06))
                        .frame(width: max(2, x(spell.end) - x(spell.start)), height: h - 18)
                        .position(x: (x(spell.start) + x(spell.end)) / 2, y: (h - 18) / 2)
                    // Culprits: rise out of the band at their strongest report, in the heat palette.
                    ForEach(Array(culprits.prefix(5).enumerated()), id: \.element.id) { i, c in
                        let size = 14 + 22 * CGFloat(c.score)
                        let levels = CGFloat(max(1, min(5, culprits.count)))
                        let step = (bandTop - 16) / levels
                        let y = 8 + step * (CGFloat(i) + 0.5)
                        let cx = min(max(x(c.peakAt), size / 2), w - size / 2)
                        let name = ProcessNames.friendly(c.process).name
                        let labelOnLeft = cx > w * 0.6
                        let heat = Self.heat(for: c.score)
                        let entrance = motion == .full ? Motion.settle.delay(0.2 + Double(i) * 0.14) : Motion.fade
                        Path { p in p.move(to: CGPoint(x: cx, y: bandTop)); p.addLine(to: CGPoint(x: cx, y: risen ? y : bandTop)) }
                            .stroke(VColor.heat(heat).opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                            .opacity(risen ? 1 : 0)
                            .animation(entrance, value: risen)
                        ZStack {
                            Circle().fill(VColor.heat(heat).opacity(0.28)).frame(width: size * 1.9, height: size * 1.9).blur(radius: 6)
                                .accessibilityHidden(true)
                            Circle().fill(RadialGradient(colors: [VColor.heat(heat), VColor.heat(heat == .critical ? .critical : ThermalLevel(rawValue: heat.rawValue + 1) ?? .critical)],
                                                         center: .topLeading, startRadius: 0, endRadius: size))
                                .frame(width: size, height: size)
                                .overlay(Circle().stroke(VColor.surface, lineWidth: 2))
                        }
                        .scaleEffect(risen || motion != .full ? 1 : 0.3)
                        .position(x: cx, y: risen ? y : bandTop)
                        .opacity(risen ? 1 : 0)
                        .animation(entrance, value: risen)
                        Text(name).font(.caption.weight(.semibold)).foregroundStyle(VColor.ink).lineLimit(1).fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(VColor.surface.opacity(0.92), in: Capsule())
                            .position(x: labelOnLeft ? cx - size / 2 - 8 - labelWidth(name) / 2 : cx + size / 2 + 8 + labelWidth(name) / 2, y: risen ? y : bandTop)
                            .opacity(risen ? 1 : 0)
                            .animation(motion == .full ? Motion.settle.delay(0.3 + Double(i) * 0.14) : Motion.fade, value: risen)
                    }
                    // Axis labels.
                    Text(from.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(VColor.ink2)
                        .position(x: 30, y: h - 6)
                    Text(to.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(VColor.ink2)
                        .position(x: w - 30, y: h - 6)
                }
            }
            .frame(height: culprits.isEmpty ? 90 : 210)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            if culprits.isEmpty {
                Text("Shaded: the hot spell. Bands: heat state from Vitals' samples.").font(.caption).foregroundStyle(VColor.ink2)
            } else {
                Text("Each dot marks when a process's strongest report was written. Bigger means more evidence.").font(.caption).foregroundStyle(VColor.ink2)
            }
        }
        .onAppear { risen = true }
        .sensoryFeedback(.impact(weight: .light), trigger: risen) { _, new in new && !culprits.isEmpty }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(culprits.isEmpty ? "Timeline around the hot spell" : "Timeline around the hot spell with leads: " + culprits.prefix(5).map { ProcessNames.friendly($0.process).name }.joined(separator: ", "))
    }
}

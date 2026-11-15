import SwiftUI
import VitalsDesign

/// The Vitals mark, alive: a phone with a pulse running through it (design/logo, concept A).
/// It is the companion's one signature image and it always tells the truth about the connection:
/// no phone = dashed outline and a flat line; looking = a sweep along the flat line;
/// connected = the pulse, with a slow glow; measuring = the pulse beating.
///
/// Motion: continuous animation only while there is something to show, 30 fps when resting,
/// display rate while measuring, and none at all under Reduce Motion (the full trace is drawn still).
struct PulseHero: View {
    enum Mood: Equatable { case absent, searching, connected, active }
    var mood: Mood

    @Environment(\.motionLevel) private var motion

    private var animating: Bool { motion.allowsContinuous && mood != .absent }

    var body: some View {
        TimelineView(.animation(minimumInterval: mood == .active ? nil : 1.0 / 30, paused: !animating)) { context in
            Canvas { g, size in
                draw(&g, size: size, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    private var label: String {
        switch mood {
        case .absent: "No iPhone connected"
        case .searching: "Looking for your iPhone"
        case .connected: "iPhone connected"
        case .active: "Measuring your iPhone"
        }
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, time: Double) {
        // Icon geometry lives in a 1024 box; fit its drawn area (about 860 × 720) into the view.
        let s = min(size.width / 860, size.height / 720)
        let t = CGAffineTransform(translationX: size.width / 2 - 512 * s, y: size.height / 2 - 512 * s).scaledBy(x: s, y: s)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y).applying(t) }
        let line = max(2.5, 24 * s)

        let phone = Path(roundedRect: CGRect(x: 318, y: 186, width: 388, height: 652), cornerRadius: 78, style: .continuous).applying(t)
        var pulse = Path()
        pulse.move(to: pt(120, 516)); pulse.addLine(to: pt(432, 516)); pulse.addLine(to: pt(492, 372))
        pulse.addLine(to: pt(556, 612)); pulse.addLine(to: pt(604, 516)); pulse.addLine(to: pt(904, 516))
        var flat = Path()
        flat.move(to: pt(120, 516)); flat.addLine(to: pt(904, 516))

        // The phone: a soft body and an outline that opens where the trace passes through it.
        g.fill(phone, with: .color(VColor.surface))
        var outline = g
        var gaps = Path()
        gaps.addRect(CGRect(x: 318 - 40, y: 516 - 34, width: 80, height: 68).applying(t))
        gaps.addRect(CGRect(x: 706 - 40, y: 516 - 34, width: 80, height: 68).applying(t))
        outline.clip(to: gaps, options: .inverse)
        let present = mood == .connected || mood == .active
        outline.stroke(phone, with: .color(present ? VColor.ink : VColor.ink2.opacity(0.7)),
                       style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round, dash: present ? [] : [line * 1.6, line * 1.9]))

        let warm = Gradient(stops: [
            .init(color: VColor.attention, location: 0), .init(color: VColor.problem, location: 0.2),
            .init(color: VColor.fine, location: 0.46), .init(color: VColor.fine, location: 1),
        ])
        let shade = GraphicsContext.Shading.linearGradient(warm, startPoint: pt(0, 372), endPoint: pt(0, 620))
        let stroke = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)

        switch mood {
        case .absent:
            g.stroke(flat, with: .color(VColor.ink2.opacity(0.45)), style: stroke)
        case .searching:
            g.stroke(flat, with: .color(VColor.ink2.opacity(0.3)), style: stroke)
            if animating { head(&g, on: flat, period: 1.6, time: time, shading: .color(VColor.ink2), style: stroke, glow: 0) }
            else { g.stroke(flat, with: .color(VColor.ink2.opacity(0.6)), style: stroke) }
        case .connected:
            g.stroke(pulse, with: shade, style: stroke)
            if animating { head(&g, on: pulse, period: 4.5, time: time, shading: shade, style: stroke, glow: line * 1.2) }
        case .active:
            g.opacity = animating ? 0.38 : 1
            g.stroke(pulse, with: shade, style: stroke)
            g.opacity = 1
            if animating { head(&g, on: pulse, period: 1.5, time: time, shading: shade, style: stroke, glow: line * 1.4) }
        }
    }

    /// A bright segment that travels along the trace, with an optional soft glow under it.
    private func head(_ g: inout GraphicsContext, on path: Path, period: Double, time: Double,
                      shading: GraphicsContext.Shading, style: StrokeStyle, glow: CGFloat) {
        let p = time.truncatingRemainder(dividingBy: period) / period * 1.35 - 0.05
        let from = max(0, p - 0.3), to = min(1, max(0, p))
        guard to > from else { return }
        let segment = path.trimmedPath(from: from, to: to)
        if glow > 0 {
            g.drawLayer { layer in
                layer.addFilter(.blur(radius: glow))
                layer.opacity = 0.7
                layer.stroke(segment, with: shading, style: StrokeStyle(lineWidth: style.lineWidth * 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        g.stroke(segment, with: shading, style: style)
    }
}

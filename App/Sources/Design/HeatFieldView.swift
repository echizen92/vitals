import SwiftUI
import VitalsKit
import VitalsDesign

/// "Living heat": thermal state as a slow gradient field. Still when nominal, restless when hot.
/// Motion level `.still` (Reduce Motion, or the phone is critical) draws one frame and stops;
/// `.calm` (serious) runs at 15 fps. The view pauses whenever it is off screen.
struct HeatFieldView: View {
    var level: ThermalLevel
    @Environment(\.motionLevel) private var motion
    @Environment(\.colorScheme) private var scheme
    @State private var visible = false
    @State private var shownIntensity: Double = 0

    var intensity: Double {
        switch level {
        case .nominal: 0.1
        case .fair: 0.35
        case .serious: 0.7
        case .critical: 1.0
        }
    }

    /// Normal heat: a short settle when the card appears, then still (no continuous cost). Hotter: restless.
    @State private var settleUntil = Date.distantPast
    var animates: Bool { visible && motion.allowsContinuous && (level != .nominal || Date() < settleUntil) }

    var body: some View {
        TimelineView(.animation(minimumInterval: motion.frameInterval ?? (1.0 / 30), paused: !animates)) { ctx in
            let t = animates ? Float(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)) : 0
            GeometryReader { geo in
                Rectangle()
                    .colorEffect(ShaderLibrary.heatField(
                        .float2(geo.size), .float(t), .float(Float(shownIntensity)),
                        .color(VColor.surface), .color(VColor.heat(.nominal).opacity(scheme == .dark ? 0.7 : 0.62)),
                        // At Normal the field stays in the cool colour only, so it never drifts toward olive or orange.
                        .color(level == .nominal ? VColor.heat(.nominal).opacity(scheme == .dark ? 0.85 : 0.75) : VColor.heat(.fair)),
                        .color(VColor.heat(level == .critical ? .critical : .serious))))
            }
        }
        .onAppear {
            visible = true; shownIntensity = intensity
            settleUntil = .now.addingTimeInterval(2.5)
            // Stop the timeline once the settle is over.
            Task { try? await Task.sleep(for: .seconds(2.6)); settleUntil = .distantPast }
        }
        .onDisappear { visible = false }
        .onChange(of: level) { _, _ in
            withAnimation(Motion.change(motion, .easeInOut(duration: 1.2))) { shownIntensity = intensity }
        }
    }
}

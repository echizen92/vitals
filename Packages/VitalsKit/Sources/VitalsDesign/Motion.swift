import SwiftUI
import VitalsKit

/// How much motion a screen may use right now. Combines Reduce Motion with the phone's thermal state:
/// Vitals must not heat the phone it is diagnosing, so animation calms down at serious and stops at critical.
public enum MotionLevel: Int, Sendable, Comparable {
    /// Reduce Motion is on, or the phone is critical: no continuous animation, cross-fades only.
    case still = 0
    /// Serious thermal state: continuous animation at a low frame rate, no particle work.
    case calm = 1
    /// Everything on.
    case full = 2

    public static func < (l: MotionLevel, r: MotionLevel) -> Bool { l.rawValue < r.rawValue }

    public static func resolve(reduceMotion: Bool, thermal: ThermalLevel) -> MotionLevel {
        if reduceMotion || thermal == .critical { return .still }
        if thermal == .serious { return .calm }
        return .full
    }

    /// Frame interval for `TimelineView(.animation(minimumInterval:))`.
    public var frameInterval: Double? {
        switch self {
        case .full: nil          // display rate, up to 120 Hz
        case .calm: 1.0 / 15
        case .still: nil
        }
    }

    public var allowsContinuous: Bool { self != .still }
}

private struct MotionLevelKey: EnvironmentKey {
    static let defaultValue: MotionLevel = .full
}

extension EnvironmentValues {
    /// Set once at the root from Reduce Motion and the live thermal state.
    public var motionLevel: MotionLevel {
        get { self[MotionLevelKey.self] }
        set { self[MotionLevelKey.self] = newValue }
    }
}

public enum Motion {
    /// The house spring: quick, settled, a touch of life.
    public static let settle = Animation.spring(duration: 0.45, bounce: 0.18)
    public static let snappy = Animation.spring(duration: 0.3, bounce: 0.25)
    public static let gentle = Animation.spring(duration: 0.8, bounce: 0.05)
    public static let fade = Animation.easeInOut(duration: 0.2)

    /// The animation to use for a state change at a given motion level.
    public static func change(_ level: MotionLevel, _ animation: Animation = settle) -> Animation {
        level == .still ? fade : animation
    }
}

extension View {
    /// Runs `animation` normally, a short fade under Reduce Motion or at critical heat.
    public func vitalsAnimation<V: Equatable>(_ animation: Animation = Motion.settle, value: V) -> some View {
        modifier(LevelAnimation(animation: animation, value: value))
    }
}

private struct LevelAnimation<V: Equatable>: ViewModifier {
    @Environment(\.motionLevel) var level
    var animation: Animation
    var value: V
    func body(content: Content) -> some View {
        content.animation(Motion.change(level, animation), value: value)
    }
}

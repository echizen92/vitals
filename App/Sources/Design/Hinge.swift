import SwiftUI

/// What the hinge reports, from SwiftUI's `onHingeChange` (iOS 27.1). Used only for effects and the
/// hinge hardware test, never for layout (the Duo HIG and checklist: size classes drive layout).
struct HingeState: Equatable {
    enum Status: String { case closed, partiallyOpen, fullyOpen, unknown }
    var status: Status
    /// Degrees; nil when the system gives no hinge (every phone but Duo, and the simulator).
    var angle: Double?
}

private struct HingeKey: EnvironmentKey { static let defaultValue: HingeState? = nil }

extension EnvironmentValues {
    var hinge: HingeState? {
        get { self[HingeKey.self] }
        set { self[HingeKey.self] = newValue }
    }
}

/// Reads the hinge and publishes it to the environment. A no-op before iOS 27.1.
struct HingeReader: ViewModifier {
    @State private var state: HingeState?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .environment(\.hinge, state)
                .onHingeChange { _, ctx in
                    guard let h = ctx.hinge else { state = nil; return }
                    let s: HingeState.Status = h.status == .closed ? .closed : h.status == .partiallyOpen ? .partiallyOpen : h.status == .fullyOpen ? .fullyOpen : .unknown
                    state = HingeState(status: s, angle: h.angle.degrees)
                }
        } else {
            content
        }
    }
}

extension View {
    func readsHinge() -> some View { modifier(HingeReader()) }
}

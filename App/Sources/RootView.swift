import SwiftUI
import VitalsKit
import VitalsDesign

/// System `TabView`, so the tab bar becomes Liquid Glass, and moves to the side strip on iPhone Duo's outer display.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboarded") private var onboarded = false

    /// Screenshot and test runs skip onboarding.
    private var skipOnboarding: Bool {
        let a = ProcessInfo.processInfo.arguments
        return ["-skipOnboarding", "-inject", "-syntheticDay", "-live"].contains { a.contains($0) }
    }

    /// `-reduceMotion` forces the Reduce Motion variants, for checking them in the Simulator.
    private var motionLevel: MotionLevel {
        let forced = ProcessInfo.processInfo.arguments.contains("-reduceMotion")
        return MotionLevel.resolve(reduceMotion: reduceMotion || forced, thermal: model.thermal)
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Check-up", systemImage: "waveform.path.ecg", value: AppTab.checkup) {
                CheckupScreen()
            }
            Tab("Heat", systemImage: "thermometer.medium", value: AppTab.heat) {
                HeatScreen()
            }
            Tab("Optimise", systemImage: "wand.and.stars", value: AppTab.optimise) {
                OptimiseScreen()
            }
            Tab("Logs", systemImage: "doc.text.magnifyingglass", value: AppTab.logs) {
                LogsScreen()
            }
            Tab("Tests", systemImage: "hand.tap", value: AppTab.tests) {
                TestsScreen()
            }
        }
        .tint(VColor.ink)
        .environment(\.motionLevel, motionLevel)
        .readsHinge()
        .fullScreenCover(isPresented: Binding(get: { !onboarded && !skipOnboarding }, set: { _ in })) {
            OnboardingView { onboarded = true }
                .environment(model)
                .environment(\.motionLevel, motionLevel)
        }
    }
}

/// Shown on every screen while simulator values are injected, so they never pass for real readings.
struct InjectionBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if model.isInjecting {
            Label("Injected values, not from this phone", systemImage: "syringe")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VColor.attention)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(VColor.attention.opacity(0.08)))
                .accessibilityLabel("Showing injected test values, not readings from this phone")
        }
    }
}

/// The app's ground behind every screen.
struct Ground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(VColor.ground.ignoresSafeArea())
    }
}

extension View {
    func vitalsGround() -> some View { modifier(Ground()) }
}

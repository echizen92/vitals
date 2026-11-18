import SwiftUI
import VitalsKit
import VitalsDesign

/// Left column: the phone, alive or not, and the connection said in plain words. Developer Mode is
/// explained where it matters and never pushed.
struct ConnectionColumn: View {
    @Environment(EngineRunner.self) private var runner

    private var mood: PulseHero.Mood {
        if runner.checking { return .searching }
        if !runner.connected { return .absent }
        return runner.running ? .active : .connected
    }

    private var headline: String {
        if runner.checking && runner.access == nil { return "Looking for your iPhone…" }
        if runner.checkProblem != nil { return "The measuring engine did not start" }
        switch runner.tier {
        case 2: return "Connected, full access"
        case 1: return "Connected: logs and battery"
        default: return "No iPhone found"
        }
    }

    var body: some View {
        @Bindable var runner = runner
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if runner.simulate { SimulatedBadge() }
                PulseHero(mood: mood)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.title2.weight(.semibold)).foregroundStyle(VColor.ink)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                    if let d = Plain.device(runner.access?.device ?? runner.device), runner.connected {
                        Text(d + (runner.access?.connection == "wifi" ? " · over Wi-Fi" : runner.access?.connection == "usb" ? " · USB" : ""))
                            .font(.callout).foregroundStyle(VColor.ink2)
                    }
                }
                .vitalsAnimation(value: headline)

                if let problem = runner.checkProblem {
                    Text("Vitals Companion could not run its measuring engine. \(problem)")
                        .font(.callout).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                    SettingsLink { Text("Open Settings") }
                } else if !runner.connected && !runner.checking {
                    NotFoundSteps()
                }

                if runner.phones.count > 1 {
                    PhonePicker()
                }

                if runner.connected {
                    VStack(alignment: .leading, spacing: Space.m) {
                        SectionTitle("This Mac can read")
                        CapabilityRow(on: true, text: "Crash reports and daily logs")
                        CapabilityRow(on: true, text: "Battery health and charging")
                        CapabilityRow(on: runner.tier >= 2, text: "What is busy and writing, live",
                                      note: runner.tier >= 2 ? nil : "Needs Developer Mode on the iPhone. Only worth it when Vitals asks for live readings; turn it off again afterwards.")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $runner.wifi) {
                        Text("Reach iPhone over Wi-Fi").font(.callout)
                    }
                    .toggleStyle(.switch)
                    // Ink on a dark ground left a white knob on a light track: on and off looked alike.
                    // The "fine" colour fills the track when on, in both themes.
                    .tint(VColor.fine)
                    .disabled(runner.running)
                    Text("For when the cable is not working, or after a restart. The iPhone must have trusted this Mac over USB once.")
                        .font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    runner.check()
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .vitalsButton(.secondary, size: .regular)
                .disabled(runner.checking || runner.running)
                .help("Check Connection (⌘R)")
            }
            .padding(Space.xl)
        }
        .scrollContentBackground(.hidden)
        .background(VColor.ground)
    }
}

/// Several iPhones reachable: list them and let the person choose. USB is preferred until they do.
private struct PhonePicker: View {
    @Environment(EngineRunner.self) private var runner
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionTitle("Which iPhone")
            ForEach(runner.phones) { p in
                let on = p.ref == runner.currentPhone?.ref
                Button { runner.chosenPhone = p.ref } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(on ? VColor.fine : VColor.ink2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.modelName).font(.callout.weight(on ? .semibold : .regular)).foregroundStyle(VColor.ink)
                            Text([p.connectionName, p.os.map { "iOS \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(VColor.ink2)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(runner.running || runner.checking)
                .accessibilityLabel(p.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Text("Vitals measures the one ticked. A phone on USB is used first unless you choose.")
                .font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What to try when no iPhone answers, in order.
private struct NotFoundSteps: View {
    private let steps = [
        "Unlock the iPhone and keep it on the Home Screen.",
        "If it asks “Trust This Computer?”, tap Trust.",
        "Use a cable that carries data, straight into the Mac.",
        "Still nothing: turn on Wi-Fi below and check again.",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(i + 1)").font(VFont.numeral(.callout, weight: .semibold)).foregroundStyle(VColor.ink)
                    Text(s).font(.callout).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Shown at the top of the column and in the title while the simulated iPhone is on.
struct SimulatedBadge: View {
    var body: some View {
        Label("Simulated iPhone: test data, not a real phone", systemImage: "testtube.2")
            .font(.caption.weight(.semibold))
            .foregroundStyle(VColor.attention)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(VColor.attention.opacity(0.12)))
            .accessibilityLabel("Simulated iPhone is on. Results are test data.")
    }
}

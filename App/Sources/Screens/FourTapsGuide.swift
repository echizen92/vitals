import SwiftUI
import VitalsKit
import VitalsDesign

/// Shows the four taps in Settings that reach the analytics files, as a short looping drawing.
/// It is a simplified sketch in Vitals' own style, not a copy of the Settings screens.
/// Reduce Motion (or critical heat) shows the same steps as a still, numbered list.
struct FourTapsGuide: View {
    var onChoose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionLevel) private var motion

    static let steps: [(screen: String, tap: String, rows: [String])] = [
        ("Settings", "Privacy & Security", ["General", "Accessibility", "Privacy & Security", "Battery"]),
        ("Privacy & Security", "Analytics & Improvements", ["Location Services", "Tracking", "Analytics & Improvements", "Apple Advertising"]),
        ("Analytics & Improvements", "Analytics Data", ["Share iPhone Analytics", "Improve Siri & Dictation", "Analytics Data"]),
        ("Analytics Data", "Analytics-2026-11-14…", ["Analytics-2026-11-15…", "Analytics-2026-11-14…", "JetsamEvent-2026-11-14…", "Photos.cpu_resource…"]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Text("Four taps in Settings, then Share.")
                        .font(VFont.title).foregroundStyle(VColor.ink)
                    if motion.allowsContinuous {
                        LoopingSteps()
                            .dynamicTypeSize(...DynamicTypeSize.xLarge)
                            .frame(height: 300)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: Space.m) {
                        ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                            StepRow(number: i + 1, text: i < 3 ? "In \(s.screen), tap \(s.tap)." : "Tap the newest Analytics file (or a report from the day the phone ran hot).")
                        }
                        StepRow(number: 5, text: "Tap Share (top right), then choose Vitals.")
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No Analytics Data list?").font(.headline)
                            Text("Turn on Share iPhone Analytics on the same screen. iOS writes one analytics file a day from then on; reports for crashes and heavy CPU use appear as they happen.")
                                .font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("Already saved files to Files? Choose them directly.").font(.subheadline).foregroundStyle(VColor.ink2)
                    Button("Choose files", action: onChoose).vitalsButton(.secondary)
                }
                .padding(Space.l)
            }
            .vitalsGround()
            .navigationTitle("Share a system file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct StepRow: View {
    var number: Int
    var text: String
    @ScaledMetric(relativeTo: .headline) private var badge: CGFloat = 28
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("\(number)").font(VFont.numeral(.headline)).foregroundStyle(VColor.ink)
                .frame(width: badge, height: badge).background(Circle().fill(VColor.fine.opacity(0.14)))
            Text(text).font(.body).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}

/// A mini screen that pages through the four steps, with a "finger" landing on the row to tap.
struct LoopingSteps: View {
    @State private var step = 0
    @State private var pressed = false
    @Environment(\.motionLevel) private var motion

    var body: some View {
        let s = FourTapsGuide.steps[step]
        VStack(spacing: 0) {
            HStack {
                Text(s.screen).font(.headline).foregroundStyle(VColor.ink)
                Spacer()
                Text("\(step + 1) of 4").font(.caption.monospacedDigit()).foregroundStyle(VColor.ink2)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            VStack(spacing: 0) {
                ForEach(s.rows, id: \.self) { row in
                    let isTarget = row == s.tap
                    HStack {
                        RoundedRectangle(cornerRadius: 5).fill(isTarget ? VColor.fine : VColor.ink2.opacity(0.3)).frame(width: 22, height: 22)
                        Text(row).font(.subheadline).foregroundStyle(VColor.ink).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(VColor.ink2)
                    }
                    .padding(.horizontal, Space.l).frame(height: 44)
                    .background(isTarget && pressed ? VColor.fine.opacity(0.18) : Color.clear)
                    .overlay(alignment: .trailing) {
                        if isTarget {
                            Circle().fill(VColor.fine.opacity(0.35)).frame(width: pressed ? 34 : 46).padding(.trailing, 60)
                                .scaleEffect(pressed ? 0.9 : 1.0).opacity(pressed ? 1 : 0.6)
                        }
                    }
                    Divider().overlay(VColor.hairline).padding(.leading, 52)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 340)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(VColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(VColor.hairline, lineWidth: 1))
        .id(step)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .task {
            // Loop: show a screen, press the row, move on. Stops when the sheet closes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.1))
                withAnimation(Motion.snappy) { pressed = true }
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(Motion.settle) { pressed = false; step = (step + 1) % 4 }
            }
        }
    }
}

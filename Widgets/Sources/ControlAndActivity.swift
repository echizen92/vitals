import WidgetKit
import SwiftUI
import AppIntents
import ActivityKit
import VitalsKit
import VitalsDesign

/// Control Center / Lock Screen control.
struct RunCheckupControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "sg.com.vitals.control.checkup") {
            ControlWidgetButton(action: RunCheckupIntent()) {
                Label("Run check-up", systemImage: "waveform.path.ecg")
            }
        }
        .displayName("Run check-up")
        .description("Opens Vitals and runs a check-up.")
    }
}

struct MonitorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitorAttributes.self) { context in
            MonitorLockScreenView(attributes: context.attributes, state: context.state)
                .padding(14)
                // Fixed dark surface with light ink: the Lock Screen does not resolve our dynamic colours
                // the same way for the tint and the content, which left dark text on a dark tint.
                .activityBackgroundTint(Color(hex: Palette.surfaceDark))
                .activitySystemActionForegroundColor(Color(hex: Palette.inkDark))
                .widgetURL(URL(string: "vitals://heat"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.state.thermal.label) } icon: {
                        RoundedRectangle(cornerRadius: 2).fill(VColor.heat(context.state.thermal)).frame(width: 6, height: 16)
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer).font(VFont.numeral(.headline)).multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.purpose).lineLimit(1)
                        Spacer()
                        if let d = context.state.drainPerHour { Text("−\(Int(d.rounded()))%/h").accessibilityLabel("draining \(Int(d.rounded())) percent per hour") }
                        if let b = context.state.batteryLevel { Text("\(Int(b * 100))%") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                RoundedRectangle(cornerRadius: 2).fill(VColor.heat(context.state.thermal)).frame(width: 6, height: 14)
                    .accessibilityLabel("Heat \(context.state.thermal.label)")
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "thermometer.medium").foregroundStyle(VColor.heat(context.state.thermal))
                    .accessibilityLabel("Heat \(context.state.thermal.label)")
            }
            .widgetURL(URL(string: "vitals://heat"))
        }
    }
}

struct MonitorLockScreenView: View {
    var attributes: MonitorAttributes
    var state: MonitorAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Watching: \(attributes.purpose)").font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if state.summary == nil {
                    Text(attributes.startedAt, style: .timer).font(VFont.numeral(.subheadline)).multilineTextAlignment(.trailing)
                }
            }
            if let summary = state.summary {
                Text(summary).font(.subheadline)
            } else {
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(VColor.heat(state.thermal)).frame(width: 6, height: 18)
                        Text(state.thermal.label).font(VFont.numeral(.title3, weight: .bold))
                    }
                    if let b = state.batteryLevel { Text("\(Int(b * 100))%").font(VFont.numeral(.title3)) }
                    if let d = state.drainPerHour { Text("−\(Int(d.rounded()))%/h").font(VFont.numeral(.title3)).accessibilityLabel("draining \(Int(d.rounded())) percent per hour") }
                    Spacer()
                }
            }
            Text("Updated \(state.updatedAt, style: .time) · updates while Vitals can run").font(.caption2).foregroundStyle(Color(hex: Palette.ink2Dark))
        }
        .foregroundStyle(Color(hex: Palette.inkDark))
    }
}

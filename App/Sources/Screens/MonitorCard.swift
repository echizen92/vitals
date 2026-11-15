import SwiftUI
import VitalsKit
import VitalsDesign

/// Start and stop a "watch my phone while I do X" session (Live Activity), and list past sessions.
struct MonitorCard: View {
    @Environment(AppModel.self) private var model
    @State private var purpose = "Gaming"
    static let purposes = ["Gaming", "Charging", "Video call", "Navigation", "Camera", "Streaming", "Something else"]

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.m) {
                if let active = model.monitor.active {
                    AdaptiveRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Watching: \(active.purpose)").font(.headline).foregroundStyle(VColor.ink)
                            Text(active.start, style: .timer).font(VFont.numeral(.title2)).foregroundStyle(VColor.ink)
                        }
                    } trailing: {
                        Button("Stop") { Task { await model.monitor.stop(model: model) } }
                            .vitalsButton(.secondary)
                    }
                    Text("Shown on the Lock Screen and in the Dynamic Island. Vitals updates it while it can run; if iOS suspends Vitals the last reading stays, with its time.")
                        .font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Watch my phone").font(.headline).foregroundStyle(VColor.ink)
                    Text("Start a session before something that heats the phone. Vitals samples every minute it can and saves a summary to the timeline.")
                        .font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                    ViewThatFits {
                        HStack { picker; startButton }
                        VStack(alignment: .leading) { picker; startButton }
                    }
                }
                if let e = model.monitor.lastError {
                    Text(e).font(.caption).foregroundStyle(VColor.attention)
                }
            }
        }
    }

    var picker: some View {
        Picker("While", selection: $purpose) { ForEach(Self.purposes, id: \.self) { Text($0) } }
            .pickerStyle(.menu).tint(VColor.ink)
    }

    var startButton: some View {
        Button { Task { await model.monitor.start(purpose: purpose, model: model) } } label: {
            Label("Start", systemImage: "play.fill")
        }
        .vitalsButton(.primary)
    }
}

struct SessionRow: View {
    let session: MonitorSessionRecord
    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            RoundedRectangle(cornerRadius: 3).fill(VColor.heat(session.peak)).frame(width: 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.purpose) · \(DayTimeFormatting.string(session.start))").font(.subheadline.weight(.semibold)).foregroundStyle(VColor.ink)
                Text(session.summaryLine).font(.caption).foregroundStyle(VColor.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

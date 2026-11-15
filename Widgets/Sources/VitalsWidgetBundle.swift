import WidgetKit
import SwiftUI
import VitalsKit
import VitalsDesign

@main
struct VitalsWidgetBundle: WidgetBundle {
    var body: some Widget {
        HealthSummaryWidget()
        HeatWidget()
        BatteryWidget()
        StorageWidget()
        RunCheckupControl()
        MonitorLiveActivity()
    }
}

struct VitalsEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

/// One provider for all four widgets. Each reload reads what the extension can see, appends one
/// (deduplicated) sample to the shared timeline, and asks to be reloaded in 15 minutes. iOS decides the
/// real cadence (roughly 15–60 minutes), which is why every widget shows "Updated …".
struct VitalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> VitalsEntry { VitalsEntry(date: .now, data: .placeholder()) }

    func getSnapshot(in context: Context, completion: @escaping (VitalsEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        // WidgetKit's completion handlers are not Sendable; they are safe to call from any thread.
        nonisolated(unsafe) let completion = completion
        Task { completion(VitalsEntry(date: .now, data: await WidgetData.load(takeSample: false))) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VitalsEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let data = await WidgetData.load(takeSample: true)
            completion(Timeline(entries: [VitalsEntry(date: data.date, data: data)], policy: .after(Date.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct WidgetGround: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { VColor.surface }
    }
}

struct HealthSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sg.com.vitals.summary", provider: VitalsProvider()) { e in
            HealthSummaryWidgetView(data: e.data).modifier(WidgetGround()).widgetURL(URL(string: "vitals://checkup"))
        }
        .configurationDisplayName("Health summary")
        .description("Status of each area from your last check-up.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HeatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sg.com.vitals.heat", provider: VitalsProvider()) { e in
            HeatWidgetView(data: e.data).modifier(WidgetGround()).widgetURL(URL(string: "vitals://heat"))
        }
        .configurationDisplayName("Heat")
        .description("Thermal state now and the last 24 hours. Each update also adds a point to Vitals' heat timeline.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sg.com.vitals.battery", provider: VitalsProvider()) { e in
            BatteryWidgetView(data: e.data).modifier(WidgetGround()).widgetURL(URL(string: "vitals://battery"))
        }
        .configurationDisplayName("Battery")
        .description("Level, charging state and recent drain.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sg.com.vitals.storage", provider: VitalsProvider()) { e in
            StorageWidgetView(data: e.data).modifier(WidgetGround()).widgetURL(URL(string: "vitals://storage"))
        }
        .configurationDisplayName("Storage")
        .description("Used and free space.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

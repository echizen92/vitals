import SwiftUI
import WidgetKit
import VitalsKit
import VitalsDesign

/// Debug: renders the real widget views at widget sizes, with the same data loader the extension uses
/// (without adding a sample). For checking layouts where the Home Screen cannot be driven.
struct WidgetGallery: View {
    @State private var data: WidgetData?
    @State private var usePlaceholder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Toggle("Placeholder data", isOn: $usePlaceholder)
                if let d = usePlaceholder ? WidgetData.placeholder() : data {
                    tile("Health summary · small", 170, 170) { HealthSummaryWidgetView(data: d, familyOverride: .systemSmall) }
                    tile("Health summary · medium", 364, 170) { HealthSummaryWidgetView(data: d, familyOverride: .systemMedium) }
                    tile("Heat · small", 170, 170) { HeatWidgetView(data: d, familyOverride: .systemSmall) }
                    tile("Heat · medium", 364, 170) { HeatWidgetView(data: d, familyOverride: .systemMedium) }
                    HStack(alignment: .top, spacing: Space.l) {
                        tile("Heat · rectangular", 172, 76, lock: true) { HeatWidgetView(data: d, familyOverride: .accessoryRectangular) }
                        tile("Heat · circular", 76, 76, lock: true) { HeatWidgetView(data: d, familyOverride: .accessoryCircular) }
                    }
                    HStack(alignment: .top, spacing: Space.l) {
                        tile("Battery · small", 170, 170) { BatteryWidgetView(data: d, familyOverride: .systemSmall) }
                        tile("Storage · small", 170, 170) { StorageWidgetView(data: d, familyOverride: .systemSmall) }
                    }
                    HStack(alignment: .top, spacing: Space.l) {
                        tile("Battery · circular", 76, 76, lock: true) { BatteryWidgetView(data: d, familyOverride: .accessoryCircular) }
                        tile("Storage · circular", 76, 76, lock: true) { StorageWidgetView(data: d, familyOverride: .accessoryCircular) }
                    }
                    tile("Battery · inline", 240, 24, lock: true) { BatteryWidgetView(data: d, familyOverride: .accessoryInline) }
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .vitalsGround()
        .navigationTitle("Widget gallery")
        .task { data = await WidgetData.load(takeSample: false) }
    }

    func tile<V: View>(_ title: String, _ w: CGFloat, _ h: CGFloat, lock: Bool = false, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(VColor.ink2)
            v()
                .padding(lock ? 4 : 16)
                .frame(width: w, height: h, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: lock ? 12 : 22, style: .continuous).fill(lock ? Color.black.opacity(0.75) : VColor.surface))
                .environment(\.colorScheme, lock ? .dark : .light)
        }
    }
}

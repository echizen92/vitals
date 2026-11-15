import SwiftUI
import WidgetKit
import VitalsKit
import VitalsDesign

// Widget views, shared by the widget extension and the app's widget gallery.
// Every widget shows when it last updated: widgets refresh on a system budget, not live.

struct UpdatedLabel: View {
    var date: Date
    var body: some View {
        Text("Updated \(date, style: .time)")
            .font(.caption2).foregroundStyle(VColor.ink2)
            .lineLimit(1).minimumScaleFactor(0.8)
    }
}

/// 24 hours of heat as a strip of bars; gaps stay empty.
struct MiniHeatStrip: View {
    var samples: [Sample]
    var end: Date
    var monochrome = false

    var body: some View {
        Canvas { ctx, size in
            let start = end.addingTimeInterval(-86_400)
            let sorted = samples.filter { $0.hasThermal && $0.takenAt >= start }.sorted { $0.takenAt < $1.takenAt }
            for (i, s) in sorted.enumerated() {
                let next = i + 1 < sorted.count ? min(sorted[i + 1].takenAt, s.takenAt.addingTimeInterval(45 * 60)) : s.takenAt.addingTimeInterval(15 * 60)
                let x0 = size.width * s.takenAt.timeIntervalSince(start) / 86_400
                let x1 = size.width * min(next, end).timeIntervalSince(start) / 86_400
                let h = size.height * CGFloat(s.thermal.rawValue + 1) / 4
                let rect = CGRect(x: x0, y: size.height - h, width: max(1, x1 - x0), height: h)
                ctx.fill(Path(rect), with: .color(monochrome ? Color.primary.opacity(0.35 + 0.2 * Double(s.thermal.rawValue)) : VColor.heat(s.thermal)))
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 0.5, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.5)))
        }
        .accessibilityHidden(true)
    }
}

struct HealthSummaryWidgetView: View {
    var data: WidgetData
    /// Set by the in-app gallery; widgets use the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var areas: [WidgetSnapshot.AreaStatus] {
        let byArea = Dictionary(uniqueKeysWithValues: (data.snapshot?.areas ?? []).map { ($0.area, $0) })
        return Area.allCases.map { byArea[$0] ?? .init(area: $0, status: .unknown, sentence: "Not checked yet") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Vitals").font(.headline).foregroundStyle(VColor.ink)
                Spacer()
                if let worst = data.snapshot?.areas.map(\.status).max() { StatusMark(worst, size: 12) }
            }
            if family == .systemMedium {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(0..<3) { row in
                        GridRow {
                            ForEach(0..<2) { col in
                                let a = areas[row * 2 + col]
                                HStack(spacing: 6) {
                                    StatusMark(a.status, size: 10)
                                    Text(a.area.shortTitle).font(.subheadline).foregroundStyle(VColor.ink).lineLimit(1)
                                    Text(a.status.label).font(.caption).foregroundStyle(VColor.status(a.status)).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(0..<3) { row in
                        GridRow {
                            ForEach(0..<2) { col in
                                let a = areas[row * 2 + col]
                                HStack(spacing: 4) {
                                    StatusMark(a.status, size: 9)
                                    Text(a.area.shortTitle).font(.caption).foregroundStyle(VColor.ink).lineLimit(1).minimumScaleFactor(0.8)
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let at = data.snapshot?.checkupAt {
                Text("Checked \(at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))").font(.caption2).foregroundStyle(VColor.ink2).lineLimit(1)
            } else {
                Text("No check-up yet").font(.caption2).foregroundStyle(VColor.ink2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vitals summary. " + areas.map { "\($0.area.title) \($0.status.label)" }.joined(separator: ", "))
    }
}

struct HeatWidgetView: View {
    var data: WidgetData
    /// Set by the in-app gallery; widgets use the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(data.thermal.rawValue), in: 0...3) {
                Image(systemName: "thermometer.medium")
            } currentValueLabel: {
                Text(data.thermal.shortLabel)
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Heat \(data.thermal.label)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Heat · \(data.thermal.label)").font(.headline).widgetAccentable()
                MiniHeatStrip(samples: data.samples24h, end: data.date, monochrome: true).frame(height: 16)
                Text("Updated \(data.date, style: .time)").font(.caption2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heat \(data.thermal.label), updated \(data.date.formatted(date: .omitted, time: .shortened))")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Heat").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(VColor.heat(data.thermal)).frame(width: 8, height: 22)
                    Text(data.thermal.label).font(VFont.numeral(.title2, weight: .bold)).foregroundStyle(VColor.ink).lineLimit(1).minimumScaleFactor(0.7)
                }
                if family == .systemMedium {
                    Text(data.thermal.meaning).font(.caption).foregroundStyle(VColor.ink2).lineLimit(2)
                }
                Spacer(minLength: 0)
                MiniHeatStrip(samples: data.samples24h, end: data.date).frame(height: family == .systemMedium ? 34 : 26)
                HStack {
                    Text("24 h").font(.caption2).foregroundStyle(VColor.ink2)
                    Spacer()
                    UpdatedLabel(date: data.date)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heat \(data.thermal.label). \(HotSpellDetector.detect(data.samples24h).count) hot spells in 24 hours. Updated \(data.date.formatted(date: .omitted, time: .shortened)).")
        }
    }
}

struct BatteryWidgetView: View {
    var data: WidgetData
    /// Set by the in-app gallery; widgets use the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var levelText: String { data.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
    var drainText: String? { data.drainPerHour.map { $0 >= 0 ? "−\(Int($0.rounded()))%/h" : "+\(Int((-$0).rounded()))%/h" } }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: data.batteryLevel ?? 0) { Image(systemName: "battery.75percent") } currentValueLabel: { Text(levelText) }
                .gaugeStyle(.accessoryCircularCapacity)
                .accessibilityLabel("Battery \(levelText)")
        case .accessoryInline:
            Text("Battery \(levelText)\(drainText.map { " · \($0)" } ?? "")")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Battery").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2)
                Text(levelText).font(VFont.numeral(.largeTitle, weight: .bold)).foregroundStyle(VColor.ink)
                    .accessibilityLabel(data.batteryLevel == nil ? "Battery level not available" : "Battery \(levelText)")
                Text(data.batteryLevel == nil ? "Level not available here" : data.charge.label).font(.caption).foregroundStyle(VColor.ink2).lineLimit(1)
                if let d = drainText, let r = data.drainPerHour {
                    Text(d + " lately").font(.caption).foregroundStyle(VColor.ink).lineLimit(1)
                        .accessibilityLabel(r >= 0 ? "draining \(Int(r.rounded())) percent per hour lately" : "charging \(Int((-r).rounded())) percent per hour lately")
                }
                Spacer(minLength: 0)
                UpdatedLabel(date: data.date)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct StorageWidgetView: View {
    var data: WidgetData
    /// Set by the in-app gallery; widgets use the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var usedFraction: Double {
        guard let t = data.storageTotal, let f = data.storageFree, t > 0 else { return 0 }
        return Double(t - f) / Double(t)
    }
    var freeText: String { data.storageFree.map { ByteFormatting.string(Double($0)) } ?? "—" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: usedFraction) { Image(systemName: "internaldrive") } currentValueLabel: { Text("\(Int(usedFraction * 100))%") }
                .gaugeStyle(.accessoryCircularCapacity)
                .accessibilityLabel("Storage \(Int(usedFraction * 100)) percent used, \(freeText) free")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2)
                Text(freeText).accessibilityLabel(data.storageFree == nil ? "Free space not available" : freeText).font(VFont.numeral(.title, weight: .bold)).foregroundStyle(VColor.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text("free").font(.caption).foregroundStyle(VColor.ink2)
                Spacer(minLength: 0)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(VColor.ink2.opacity(0.2))
                        Capsule().fill(usedFraction > 0.95 ? VColor.problem : usedFraction > 0.9 ? VColor.attention : VColor.fine)
                            .frame(width: g.size.width * usedFraction)
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("\(Int(usedFraction * 100))% used").font(.caption2).foregroundStyle(VColor.ink2)
                    Spacer()
                    UpdatedLabel(date: data.date)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

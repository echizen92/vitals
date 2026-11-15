import SwiftUI
import Charts
import VitalsKit
import VitalsDesign

enum TimelineRange: String, CaseIterable, Identifiable {
    case day = "24 hours", week = "7 days"
    var id: String { rawValue }
    var seconds: TimeInterval { self == .day ? 86_400 : 7 * 86_400 }
}

struct HeatScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var range: TimelineRange = .day
    @State private var path = NavigationPath()

    var window: (Date, Date) { (Date.now.addingTimeInterval(-range.seconds), Date.now) }
    var visible: [Sample] { model.samples.filter { $0.takenAt >= window.0 } }
    var spells: [HotSpell] { HotSpellDetector.detect(model.samples).filter { $0.end >= window.0 }.reversed() }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let columns = hSize == .regular ? [GridItem(.flexible(), spacing: Space.l, alignment: .top), GridItem(.flexible(), alignment: .top)] : [GridItem(.flexible())]
                LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        NowCard(thermal: model.thermal, latest: model.samples.last)
                        MonitorCard()
                        timeline
                    }
                    spellList
                }
                .padding(Space.l)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .vitalsGround()
            .navigationTitle("Heat")
            .navigationDestination(for: HotSpell.self) { HotSpellDetailView(spell: $0) }
            .navigationDestination(for: LogEvent.self) { RawReportView(event: $0) }
            .refreshable { await model.takeSample(source: .app) }
        }
    }

    var timeline: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            AdaptiveRow {
                SectionTitle("Timeline")
            } trailing: {
                Picker("Range", selection: $range) {
                    ForEach(TimelineRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 200, maxWidth: 260)
            }
            Panel {
                HeatTimelineChart(samples: visible.filter(\.hasThermal), spells: spells, sessions: model.sessions, from: window.0, to: window.1)
            }
            CoverageNote(samples: model.samples, from: window.0, to: window.1)
            let temps = visible.filter { $0.temperatureC != nil }
            if !temps.isEmpty {
                SectionTitle("Battery temperature")
                Panel { TemperatureChart(samples: temps) }
            }
            if visible.contains(where: { $0.source == .fixture }) {
                Label("Includes synthetic or injected samples (Simulator testing). They never go into reports or widgets.", systemImage: "syringe")
                    .font(.caption).foregroundStyle(VColor.attention)
            }
        }
    }

    var spellList: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            let recentSessions = model.sessions.filter { $0.end >= window.0 }.reversed()
            if !recentSessions.isEmpty {
                SectionTitle("Watch sessions")
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) {
                        ForEach(Array(recentSessions)) { SessionRow(session: $0) }
                    }
                }
            }
            SectionTitle("Hot spells")
            if spells.isEmpty {
                Panel {
                    Text(visible.count < 4
                         ? "Not enough samples yet. Vitals samples when it is open, during background refresh and when a widget updates. Add a Heat widget to fill in the day."
                         : "No hot spells in this period. A hot spell is a run of samples where iOS reported serious or critical heat.")
                        .font(.subheadline).foregroundStyle(VColor.ink2)
                }
            } else {
                ForEach(spells) { spell in
                    NavigationLink(value: spell) { HotSpellRow(spell: spell) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Current state with the living heat field behind it.
struct NowCard: View {
    var thermal: ThermalLevel
    var latest: Sample?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HeatFieldView(level: thermal)
                .frame(minHeight: 260)
                .accessibilityHidden(true)
            // A soft scrim over the whole card keeps text above the field at AA contrast in both appearances.
            LinearGradient(stops: [.init(color: VColor.surface.opacity(0), location: 0.15), .init(color: VColor.surface.opacity(0.9), location: 0.55)],
                           startPoint: .top, endPoint: .bottom)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                InjectionBanner()
                Text("Right now").font(.subheadline.weight(.medium)).foregroundStyle(VColor.ink2)
                Text(thermal.label).font(VFont.numeral(.largeTitle, weight: .bold)).foregroundStyle(VColor.ink)
                Text(thermal.meaning).font(.subheadline).foregroundStyle(VColor.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ProvenanceTag(.measured)
                    Text("iPhone reports heat levels, not degrees").font(.caption).foregroundStyle(VColor.ink2)
                }
            }
            .padding(Space.l)
        }
        .clipShape(RoundedRectangle(cornerRadius: Space.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct HeatTimelineChart: View {
    var samples: [Sample]
    var spells: [HotSpell]
    var sessions: [MonitorSessionRecord] = []
    var from: Date
    var to: Date
    @State private var selected: Date?
    @State private var tick = 0

    /// Samples further apart than this are not joined: Vitals did not see the gap.
    static let maxJoin: TimeInterval = 45 * 60

    struct Band: Identifiable { let id: Int; let start: Date; let end: Date; let thermal: ThermalLevel }

    var bands: [Band] {
        samples.enumerated().map { i, s in
            let next = i + 1 < samples.count ? samples[i + 1].takenAt : min(to, s.takenAt.addingTimeInterval(10 * 60))
            return Band(id: i, start: s.takenAt, end: min(next, s.takenAt.addingTimeInterval(Self.maxJoin)), thermal: s.thermal)
        }
    }

    /// Battery samples split into runs at gaps, so the line breaks where data is missing.
    var batteryRuns: [(Int, Sample)] {
        var run = 0
        var out: [(Int, Sample)] = []
        var last: Date?
        for s in samples where s.batteryLevel != nil {
            if let l = last, s.takenAt.timeIntervalSince(l) > Self.maxJoin { run += 1 }
            out.append((run, s)); last = s.takenAt
        }
        return out
    }

    var selectedSample: Sample? {
        guard let selected else { return nil }
        return samples.min { abs($0.takenAt.timeIntervalSince(selected)) < abs($1.takenAt.timeIntervalSince(selected)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            readout
            // Heat on its own strip: colour is the level. Battery below on its own percentage axis,
            // so a bar's height is never read as a percentage.
            Text("Heat").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2)
            Chart {
                ForEach(sessions.filter { $0.end >= from }) { s in
                    RectangleMark(xStart: .value("Session start", s.start), xEnd: .value("Session end", s.end), yStart: .value("Low", 0), yEnd: .value("High", 1))
                        .foregroundStyle(VColor.fine.opacity(0.12))
                }
                ForEach(bands) { b in
                    RectangleMark(xStart: .value("Start", b.start), xEnd: .value("End", b.end), yStart: .value("Low", 0.08), yEnd: .value("High", 0.92))
                        .foregroundStyle(VColor.heat(b.thermal).opacity(b.thermal == .nominal ? 0.55 : 0.95))
                }
                if let s = selectedSample { RuleMark(x: .value("Selected", s.takenAt)).foregroundStyle(VColor.ink2).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
            .chartXScale(domain: from...to)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1)
            .chartXSelection(value: $selected)
            .frame(height: 40)
            Text("Battery").font(.caption.weight(.semibold)).foregroundStyle(VColor.ink2).padding(.top, Space.s)
            Chart {
                ForEach(batteryRuns, id: \.1.takenAt) { run, s in
                    AreaMark(x: .value("Time", s.takenAt), y: .value("Battery", (s.batteryLevel ?? 0) * 100), series: .value("Run", run))
                        .foregroundStyle(VColor.fine.opacity(0.12))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", s.takenAt), y: .value("Battery", (s.batteryLevel ?? 0) * 100), series: .value("Run", run))
                        .foregroundStyle(VColor.ink)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                if let s = selectedSample {
                    RuleMark(x: .value("Selected", s.takenAt)).foregroundStyle(VColor.ink2).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if let b = s.batteryLevel {
                        PointMark(x: .value("Selected", s.takenAt), y: .value("Battery", b * 100)).foregroundStyle(VColor.ink).symbolSize(40)
                    }
                }
            }
            .chartXScale(domain: from...to)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(VColor.hairline)
                    AxisValueLabel(format: to.timeIntervalSince(from) > 2 * 86_400 ? .dateTime.weekday(.abbreviated) : .dateTime.hour())
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                    AxisGridLine().foregroundStyle(VColor.hairline)
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))%") } }
                }
            }
            .chartXSelection(value: $selected)
            .frame(height: 130)
            // Haptics: a light tick for each sample the scrubber passes, a firmer one entering a hot spell.
            .sensoryFeedback(.selection, trigger: selectedSample?.takenAt)
            .sensoryFeedback(.impact(weight: .medium), trigger: tick)
            .onChange(of: selectedSample?.takenAt) { _, new in
                guard let new else { return }
                if spells.contains(where: { new >= $0.start && new <= $0.end }) { tick += 1 }
            }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heat and battery timeline")
        .accessibilityValue(accessibilitySummary)
    }

    @ViewBuilder var readout: some View {
        if let s = selectedSample {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) { readoutItems(s) }
                VStack(alignment: .leading, spacing: 2) { readoutItems(s) }
            }
            .foregroundStyle(VColor.ink)
            .accessibilityElement(children: .combine)
        } else {
            Text("Drag across the chart to read a sample.").font(.subheadline).foregroundStyle(VColor.ink2)
        }
    }

    @ViewBuilder func readoutItems(_ s: Sample) -> some View {
        Text(s.takenAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold))
        Text(s.thermal.label).font(.subheadline).foregroundStyle(VColor.heatText(s.thermal))
        if let b = s.batteryLevel { Text("\(Int(b * 100))%").font(.subheadline.monospacedDigit()) }
        Text(s.charge.label).font(.subheadline).foregroundStyle(VColor.ink2)
        Text(s.source.rawValue).font(.caption2).foregroundStyle(VColor.ink2)
    }

    var legend: some View {
        ViewThatFits {
            HStack(spacing: Space.m) { legendItems }
            VStack(alignment: .leading, spacing: 6) { legendItems }
        }
        .font(.caption).foregroundStyle(VColor.ink2)
    }

    @ViewBuilder var legendItems: some View {
        ForEach(ThermalLevel.allCases, id: \.self) { t in
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(VColor.heat(t)).frame(width: 12, height: 10)
                Text(t.label)
            }
        }

    }

    var accessibilitySummary: String {
        let hot = samples.filter { $0.thermal.isHot }.count
        return "\(samples.count) samples, \(hot) hot, \(spells.count) hot spells."
    }
}

struct CoverageNote: View {
    var samples: [Sample]
    var from: Date
    var to: Date
    var body: some View {
        let c = Coverage.of(samples, from: from, to: to)
        Text("\(c.sampleCount) samples, covering \(Int((c.fraction * 100).rounded()))% of hours. Gaps are times Vitals had no chance to look.")
            .font(.caption).foregroundStyle(VColor.ink2)
    }
}

struct HotSpellRow: View {
    let spell: HotSpell
    var body: some View {
        Panel {
            HStack(alignment: .top, spacing: Space.m) {
                RoundedRectangle(cornerRadius: 4).fill(VColor.heat(spell.peak)).frame(width: 6).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(spell.peak.label) · \(DayTimeFormatting.string(spell.start))")
                        .font(.headline).foregroundStyle(VColor.ink)
                    Text(spell.summaryLine).font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(VColor.ink2).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the spell and lets you find the cause")
    }
}

extension HotSpell {
    var summaryLine: String {
        var parts: [String] = []
        parts.append(sampleCount == 1 ? "Seen once" : "About \(DurationFormatting.string(seconds: max(duration, 60)))")
        if ongoing { parts.append("may still be going on") }
        parts.append(wasCharging ? "while charging" : "on battery")
        if let d = drainPerHour { parts.append("draining \(Int(d.rounded()))%/h") }
        return parts.joined(separator: ", ")
    }
}


/// Battery temperature from Mac companion captures. iPhones do not report degrees to apps; these points come
/// from the Mac reading the phone over USB or Wi-Fi.
struct TemperatureChart: View {
    var samples: [Sample]
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Chart(samples, id: \.takenAt) { s in
                LineMark(x: .value("Time", s.takenAt), y: .value("°C", s.temperatureC ?? 0))
                    .foregroundStyle(VColor.heat(.serious))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(VColor.hairline); AxisValueLabel(format: .dateTime.hour().minute()) } }
            .chartYAxis { AxisMarks(position: .trailing) { v in AxisGridLine().foregroundStyle(VColor.hairline); AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))°") } } } }
            .frame(height: 140)
            .accessibilityLabel("Battery temperature")
            .accessibilityValue("From \(Int(samples.compactMap(\.temperatureC).min() ?? 0)) to \(Int(samples.compactMap(\.temperatureC).max() ?? 0)) degrees Celsius")
            HStack(spacing: 6) {
                ProvenanceTag(.parsedFromLog)
                Text("Mac companion capture · \(samples.count) points").font(.caption2).foregroundStyle(VColor.ink2)
            }
        }
    }
}

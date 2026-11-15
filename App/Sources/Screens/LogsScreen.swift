import SwiftUI
import UniformTypeIdentifiers
import VitalsKit
import VitalsDesign

struct LogsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showGuide = false
    @State private var showPicker = false
    @State private var showScreenshot = false

    var crashes: [CrashSummary] { CrashSummary.build(from: model.events) }
    var panics: [LogEvent] { model.events.filter { $0.kind == .panic }.sorted { $0.timestamp > $1.timestamp } }
    var heavy: [(String, [LogEvent])] {
        Dictionary(grouping: model.events.filter { [.cpuResource, .wakeups, .diskWrites].contains($0.kind) }, by: \.process)
            .sorted { $0.value.count > $1.value.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    IntroCard(showGuide: $showGuide, showPicker: $showPicker)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowInsets(EdgeInsets(top: Space.s, leading: 0, bottom: Space.s, trailing: 0)).listRowBackground(Color.clear)
                }
                if let p = model.importing {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reading \(p.fileName)").font(.subheadline.weight(.medium))
                            ProgressView(value: p.fraction).tint(VColor.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                if let last = model.lastImport {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(last.message).font(.subheadline.weight(.semibold)).foregroundStyle(VColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(last.fileName).font(.caption).foregroundStyle(VColor.ink2).lineLimit(1).truncationMode(.middle)
                            }
                        } icon: { StatusMark(last.failed ? .problem : .good, size: 12) }
                    }
                }
                Section {
                    Button { showScreenshot = true } label: {
                        ReliefRow(symbol: "text.viewfinder", title: "Battery screenshot", subtitle: "Per-app battery use and maximum capacity exist only in Settings > Battery. Share a screenshot; Vitals reads it here and you confirm.")
                    }.buttonStyle(.plain)
                }
                if let h = model.batteryHealth {
                    Section { BatteryHealthCard(health: h) } header: { SectionTitle("Battery health") }
                }
                if !crashes.isEmpty {
                    Section {
                        ForEach(crashes.prefix(12)) { c in
                            NavigationLink(value: c) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ProcessName(raw: c.process)
                                        Text("Last \(DayTimeFormatting.string(c.last))").font(.caption).foregroundStyle(VColor.ink2)
                                    }
                                    Spacer()
                                    Text(countText(c)).font(.subheadline.monospacedDigit()).foregroundStyle(VColor.ink2)
                                }
                            }
                        }
                    } header: { SectionTitle("Crashes and hangs") } footer: { ProvenanceTag(.parsedFromLog) }
                }
                if !panics.isEmpty {
                    Section {
                        ForEach(panics) { e in
                            NavigationLink(value: e) { EventRow(event: e) }
                        }
                    } header: { SectionTitle("Unexpected restarts") }
                }
                if !heavy.isEmpty {
                    Section {
                        ForEach(heavy.prefix(10), id: \.0) { name, events in
                            NavigationLink(value: events.sorted { $0.timestamp > $1.timestamp }.first!) {
                                HStack {
                                    ProcessName(raw: name)
                                    Spacer()
                                    Text("\(events.count) report\(events.count == 1 ? "" : "s")").font(.subheadline).foregroundStyle(VColor.ink2)
                                }
                            }
                        }
                    } header: { SectionTitle("Flagged for heavy use") } footer: {
                        Text("iOS writes these when a process goes over its CPU, wake-up or disk-write budget.")
                    }
                }
                Section {
                    if model.imports.isEmpty {
                        Text("Nothing shared yet.").foregroundStyle(VColor.ink2)
                    }
                    ForEach(model.imports) { r in
                        ImportRow(record: r)
                            .swipeActions { Button("Delete", role: .destructive) { Task { await model.deleteImport(r) } } }
                    }
                } header: { SectionTitle("Shared files") } footer: {
                    Text("Copies are kept inside Vitals so the report can include them. Swipe to delete one.")
                }
            }
            .scrollContentBackground(.hidden)
            .vitalsGround()
            .navigationTitle("Logs")
            .navigationDestination(for: CrashSummary.self) { CrashDetailView(summary: $0) }
            .navigationDestination(for: LogEvent.self) { RawReportView(event: $0) }
            .sheet(isPresented: $showGuide) { FourTapsGuide(onChoose: { showGuide = false; showPicker = true }) }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { await model.importFiles(at: urls) }
            }
            .sheet(isPresented: $showScreenshot) { BatteryScreenshotImport() }
        }
    }

    func countText(_ c: CrashSummary) -> String {
        [c.crashes > 0 ? "\(c.crashes) crash\(c.crashes == 1 ? "" : "es")" : nil, c.hangs > 0 ? "\(c.hangs) hang\(c.hangs == 1 ? "" : "s")" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

/// One clear action: share today's daily analytics file. Choosing files is the quieter second way.
struct IntroCard: View {
    @Binding var showGuide: Bool
    @Binding var showPicker: Bool
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: Space.m) {
                Image(systemName: "doc.text.magnifyingglass").font(.title2).foregroundStyle(VColor.ink).accessibilityHidden(true)
                Text("Share today's daily file").font(VFont.title).foregroundStyle(VColor.ink).accessibilityAddTraits(.isHeader)
                Text("iOS writes one each morning: busy apps, disk writes, heat and restarts. Vitals reads it here, on the phone.")
                    .font(.subheadline).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
                Button { showGuide = true } label: {
                    Text("Show me how").frame(maxWidth: .infinity)
                }
                .vitalsButton(.primary)
                .accessibilityHint("Four taps in Settings, then share the file to Vitals")
                Button { showPicker = true } label: {
                    Label("Or choose files you already saved", systemImage: "folder").font(.subheadline.weight(.medium))
                }
                .tint(VColor.ink)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct BatteryHealthCard: View {
    let health: BatteryHealth
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xl) { values }
                VStack(alignment: .leading, spacing: Space.m) { values }
            }
            capacityFooter
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder var values: some View {
                if let m = health.effectiveMaxCapacity {
                    BigValue("\(Int(m.value.rounded()))", unit: "%", caption: "Maximum capacity")
                }
                if let c = health.cycleCount {
                    BigValue("\(c)", caption: "Charge cycles")
                }
    }

    @ViewBuilder var capacityFooter: some View {
            HStack(spacing: 6) {
                ProvenanceTag(health.effectiveMaxCapacity?.provenance ?? .parsedFromLog, unverified: true)
                Text("\(health.sourceFile), \(health.asOf.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(VColor.ink2).lineLimit(2)
            }
            Text("Key names in the analytics file are not documented by Apple. Compare with Settings > Battery > Battery Health once.")
                .font(.caption).foregroundStyle(VColor.ink2)
    }
}

/// Titled by what the file is ("Daily analytics, 15 Nov"); the file name is secondary.
struct ImportRow: View {
    let record: ImportRecord
    var title: String {
        let day = (record.coversDate ?? record.importedAt).formatted(.dateTime.day().month(.abbreviated))
        return "\(record.kind.label), \(day)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(VColor.ink)
                Spacer()
                Text(ByteFormatting.string(Double(record.byteSize))).font(.caption).foregroundStyle(VColor.ink2)
            }
            Text(record.fileName).font(.caption).foregroundStyle(VColor.ink2).lineLimit(1).truncationMode(.middle)
            ForEach(record.notes.prefix(3), id: \.self) { Text($0).font(.caption).foregroundStyle(VColor.ink2) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EventRow: View {
    let event: LogEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                ProcessName(raw: event.process, font: .subheadline.weight(.semibold))
                Text("· \(event.kind.label.lowercased())").font(.subheadline).foregroundStyle(VColor.ink2)
            }
            Text(DayTimeFormatting.string(event.timestamp)).font(.caption).foregroundStyle(VColor.ink2)
            if let d = event.detail { Text(d).font(VFont.mono).foregroundStyle(VColor.ink2).lineLimit(2) }
        }
    }
}

struct CrashDetailView: View {
    let summary: CrashSummary
    var body: some View {
        List {
            ForEach(summary.events) { e in
                NavigationLink(value: e) { EventRow(event: e) }
            }
        }
        .scrollContentBackground(.hidden)
        .vitalsGround()
        .navigationTitle(ProcessNames.friendly(summary.process).name)
    }
}

struct RawReportView: View {
    let event: LogEvent
    @Environment(AppModel.self) private var model
    var body: some View {
        let record = model.record(for: event)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                EventRow(event: event)
                HStack(spacing: 6) {
                    ProvenanceTag(.parsedFromLog)
                    Text(record?.fileName ?? "").font(.caption2).foregroundStyle(VColor.ink2)
                }
                Divider()
                if let text = ImportLibrary.rawText(for: event, record: record) {
                    Text(text).font(VFont.mono).textSelection(.enabled).foregroundStyle(VColor.ink)
                } else {
                    Text("The original file is no longer stored.").foregroundStyle(VColor.ink2)
                }
            }
            .padding()
        }
        .vitalsGround()
        .navigationTitle("Raw report")
        .navigationBarTitleDisplayMode(.inline)
    }
}

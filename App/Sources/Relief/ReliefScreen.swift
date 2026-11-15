import SwiftUI
import VitalsKit
import VitalsDesign

/// Quick relief (plan §5.14a): short actions that leave the phone better now, in three honest tiers that say
/// who does the work. Every action records before and after and reports the result, including "no change".
/// There is no "clear RAM" or "boost" button: iOS gives apps no way to do that, and a fake one would be a lie.
struct ReliefScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmClear = false
    @State private var detail: AdviceCatalog.Action?

    let guided = ["guided.restart", "guided.coolDown", "guided.offloadApps", "guided.safariData", "guided.backgroundRefresh", "guided.messagesAttachments"]

    var body: some View {
        List {
            if let m = model.reliefMessage {
                Section { Label(m, systemImage: "info.circle").foregroundStyle(VColor.ink) }
            }
            Section {
                NavigationLink { PhotoCleanupView() } label: {
                    ReliefRow(symbol: "photo.on.rectangle", title: "Photos and videos clean-up", subtitle: "Duplicates, bursts, old screenshots, recordings, big videos. You review; deleted items go to Recently Deleted.")
                }
                Button { confirmClear = true } label: {
                    ReliefRow(symbol: "trash", title: "Clear Vitals' own imported logs", subtitle: "Removes the files you shared into Vitals.")
                }
                .buttonStyle(.plain)
            } header: { TierHeader(relief: .vitals) }

            Section {
                if ReliefShortcut.anyBundled {
                    ForEach(ReliefShortcut.allCases.filter { $0.bundledFile != nil }) { s in
                        ShortcutReliefRow(shortcut: s)
                    }
                    // Shortcuts runs a shortcut by name, so each one (and its Undo) is added to the Shortcuts app once.
                    ShareLink(items: ReliefShortcut.allBundledFiles) { Label("Add the Vitals shortcuts", systemImage: "plus.square.on.square") }
                } else {
                    Text("The Vitals Relief shortcuts are not in this build yet. They are built and signed on a Mac (see shortcuts/README.md). Until then, the guided steps below do the same by hand.")
                        .font(.subheadline).foregroundStyle(VColor.ink2)
                }
            } header: { TierHeader(relief: .shortcut) } footer: {
                Text("Shortcuts can turn on Low Power Mode, dim the screen or set a charge limit, which apps cannot. Each one has an Undo.")
            }

            Section {
                ForEach(guided.compactMap(AdviceCatalog.action), id: \.id) { a in
                    Button { detail = a } label: {
                        ReliefRow(symbol: "list.number", title: a.title, subtitle: a.effort + (model.outcome(for: a.id).map { " · last time: \($0.verdict.label.lowercased())" } ?? ""))
                    }
                    .buttonStyle(.plain)
                }
            } header: { TierHeader(relief: .guided) }

            Section {
                Text(AdviceCatalog.myth("clearRam") ?? "")
                    .font(.subheadline).foregroundStyle(VColor.ink2)
            } header: { SectionTitle("Why there is no “clear RAM” button") }
        }
        .scrollContentBackground(.hidden)
        .vitalsGround()
        .navigationTitle("Relief")
        .sheet(item: $detail) { a in NavigationStack { ActionDetailView(action: a, findingID: nil) } }
        .confirmationDialog("Remove every file you shared into Vitals?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    let before = await model.snapshot()
                    for r in model.imports { await model.deleteImport(r) }
                    ImportLibrary.deleteAllFiles()
                    if let a = AdviceCatalog.action("vitals.clearOwnData") {
                        let rec = await model.markDone(a, finding: nil, performedBy: "vitals", before: before)
                        model.reliefMessage = model.actions.first { $0.id == rec.id }?.outcomeText
                    }
                }
            }
        } message: { Text("Imported evidence leaves Vitals' timeline and reports. The originals in Settings are not touched.") }
    }
}

struct TierHeader: View {
    var relief: AdviceCatalog.Relief
    var body: some View {
        Label(relief.label, systemImage: relief == .vitals ? "checkmark.seal" : relief == .shortcut ? "square.2.layers.3d" : "hand.point.up.left")
            .font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(VColor.ink2)
    }
}

struct ReliefRow: View {
    var symbol: String
    var title: String
    var subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(VColor.ink).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(VColor.ink)
                Text(subtitle).font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct ShortcutReliefRow: View {
    let shortcut: ReliefShortcut
    @Environment(AppModel.self) private var model
    var body: some View {
        AdaptiveRow {
            ReliefRow(symbol: shortcut.symbol, title: String(shortcut.rawValue.dropFirst("Vitals ".count)),
                      subtitle: AdviceCatalog.action(shortcut.actionID)?.why ?? "")
        } trailing: {
            HStack {
                Button("Run") { Task { await model.runReliefShortcut(shortcut) } }.vitalsButton(.secondary)
                    .accessibilityLabel("Run \(shortcut.rawValue)")
                if shortcut.undo != nil {
                    Button("Undo") { Task { await model.runReliefShortcut(shortcut, undo: true) } }.vitalsButton(.secondary)
                        .accessibilityLabel("Undo \(shortcut.rawValue)")
                }
            }
        }
    }
}

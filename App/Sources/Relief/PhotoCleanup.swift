import SwiftUI
import Photos
import VitalsKit
import VitalsDesign

/// "Vitals does it": photo and video clean-up (plan §5.14a). Permission is asked only when the person opens
/// this screen. Everything is analysed on the phone. Deletion goes through the system confirmation into
/// Recently Deleted. Sizes before deletion are ESTIMATES (PhotoKit has no public file-size API); the result
/// is then MEASURED as free space before and after.
@MainActor
@Observable
final class PhotoCleanupModel {
    struct Group: Identifiable {
        let id: String
        let title: String
        let why: String
        var assets: [PHAsset]
        var selected: Set<String>
        var estimatedBytes: Double { assets.filter { selected.contains($0.localIdentifier) }.map(PhotoCleanupModel.estimate).reduce(0, +) }
    }

    var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var groups: [Group] = []
    var scanning = false
    var lastResult: String?

    func requestAndScan() async {
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { return }
        scanning = true
        defer { scanning = false }
        groups = await Task.detached(priority: .userInitiated) { Self.scan() }.value
    }

    nonisolated static func scan() -> [Group] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        opts.includeAllBurstAssets = true
        let all = PHAsset.fetchAssets(with: opts)
        var screenshots: [PHAsset] = [], recordings: [PHAsset] = [], bursts: [String: [PHAsset]] = [:], videos: [PHAsset] = []
        var lastKey: String?, lastAsset: PHAsset?
        var duplicates: [PHAsset] = []
        let oldCutoff = Date.now.addingTimeInterval(-30 * 86_400)
        all.enumerateObjects { a, _, _ in
            if a.mediaSubtypes.contains(.photoScreenshot), (a.creationDate ?? .now) < oldCutoff { screenshots.append(a) }
            if a.mediaSubtypes.contains(.videoScreenRecording) { recordings.append(a) }
            if let b = a.burstIdentifier { bursts[b, default: []].append(a) }
            if a.mediaType == .video { videos.append(a) }
            // Likely duplicates: same kind, same pixel size and duration, taken within the same second.
            let key = "\(a.mediaType.rawValue)-\(a.pixelWidth)x\(a.pixelHeight)-\(Int(a.duration))-\(Int((a.creationDate ?? .distantPast).timeIntervalSince1970))"
            if key == lastKey, lastAsset != nil { duplicates.append(a) }
            lastKey = key; lastAsset = a
        }
        // Keep the one the system picked for each burst; offer the rest.
        let burstExtras = bursts.values.flatMap { shots in
            shots.filter { !$0.burstSelectionTypes.contains(.autoPick) && !$0.burstSelectionTypes.contains(.userPick) }
        }
        let bigVideos = videos.sorted { estimate($0) > estimate($1) }.prefix(20)
        func g(_ id: String, _ t: String, _ w: String, _ a: [PHAsset], preselect: Bool) -> Group {
            Group(id: id, title: t, why: w, assets: a, selected: preselect ? Set(a.map(\.localIdentifier)) : [])
        }
        return [
            g("dupes", "Likely duplicates", "Same size and length, taken in the same second. One copy of each is kept.", duplicates, preselect: true),
            g("bursts", "Extra burst shots", "Burst photos other than the one chosen as the burst's best.", Array(burstExtras), preselect: false),
            g("screenshots", "Screenshots older than 30 days", "Usually kept by accident.", screenshots, preselect: false),
            g("recordings", "Screen recordings", "Often large and rarely rewatched.", recordings, preselect: false),
            g("videos", "Largest videos", "Review these one by one. Nothing is selected for you.", Array(bigVideos), preselect: false),
        ].filter { !$0.assets.isEmpty }
    }

    /// Rough size from pixels and duration. Labelled "about" everywhere it is shown.
    nonisolated static func estimate(_ a: PHAsset) -> Double {
        let px = Double(a.pixelWidth * a.pixelHeight)
        if a.mediaType == .video {
            let mbPerMin = px >= 8_000_000 ? 50.0 : px >= 2_000_000 ? 17.0 : 8.0
            return a.duration / 60 * mbPerMin * 1e6
        }
        return px * 0.25
    }

    /// PhotoKit runs the change block on its own queue, so it must not be main-actor isolated
    /// (Swift 6 traps if it is). The system then shows its own delete confirmation.
    nonisolated static func deleteAssets(_ ids: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges(Self.deleteBlock(ids))
    }

    nonisolated static func deleteBlock(_ ids: [String]) -> @Sendable () -> Void {
        { PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)) }
    }

    func delete(_ ids: Set<String>, model: AppModel) async {
        let before = await model.snapshot()
        do {
            try await Self.deleteAssets(Array(ids))
            if let a = AdviceCatalog.action("vitals.photoCleanup") {
                let rec = await model.markDone(a, finding: "storage", performedBy: "vitals", before: before)
                // Free space returns once iOS empties Recently Deleted; the measured change now may be small.
                lastResult = model.actions.first { $0.id == rec.id }?.outcomeText
                    ?? "Moved \(ids.count) \(ids.count == 1 ? "item" : "items") to Recently Deleted. The space comes back when Recently Deleted is emptied (after 30 days, or now from the Photos app)."
            }
            await requestAndScan()
        } catch {
            lastResult = "Nothing was deleted (\(error.localizedDescription))."
        }
    }
}

struct PhotoCleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var cleanup = PhotoCleanupModel()

    var body: some View {
        List {
            Section {
                Text("Vitals looks through your library on this phone and suggests what to delete. You review everything; nothing goes until you confirm, and deleted items stay in Recently Deleted for 30 days.")
                    .font(.subheadline).foregroundStyle(VColor.ink2)
            }
            switch cleanup.status {
            case .notDetermined:
                Section { Button("Allow Photos access and scan") { Task { await cleanup.requestAndScan() } }.vitalsButton(.primary) }
            case .denied, .restricted:
                Section { Text("Photos access is off. Settings > Apps > Vitals > Photos to allow it.").foregroundStyle(VColor.attention) }
            default:
                if cleanup.scanning { Section { HStack { ProgressView(); Text("Scanning on this phone…") } } }
                if cleanup.groups.isEmpty && !cleanup.scanning {
                    Section { Text("Nothing obvious to clean up.").foregroundStyle(VColor.ink2) }
                }
                ForEach($cleanup.groups) { $g in
                    Section {
                        Text(g.why).font(.caption).foregroundStyle(VColor.ink2)
                        ForEach(g.assets.prefix(60), id: \.localIdentifier) { a in
                            Toggle(isOn: Binding(get: { g.selected.contains(a.localIdentifier) },
                                                 set: { on in if on { g.selected.insert(a.localIdentifier) } else { g.selected.remove(a.localIdentifier) } })) {
                                AssetRow(asset: a)
                            }
                            .tint(VColor.ink)
                        }
                        if !g.selected.isEmpty {
                            Button(role: .destructive) { Task { await cleanup.delete(g.selected, model: model) } } label: {
                                Text("Delete \(g.selected.count) (about \(ByteFormatting.string(g.estimatedBytes)))")
                            }
                        }
                    } header: { SectionTitle("\(g.title) · \(g.assets.count)") }
                }
            }
            if let r = cleanup.lastResult {
                Section { Label(r, systemImage: "checkmark.circle").foregroundStyle(VColor.ink) } header: { SectionTitle("Result") }
            }
        }
        .scrollContentBackground(.hidden)
        .vitalsGround()
        .navigationTitle("Photos clean-up")
        .task { if cleanup.status == .authorized || cleanup.status == .limited { await cleanup.requestAndScan() } }
    }
}

struct AssetRow: View {
    let asset: PHAsset
    @State private var image: UIImage?
    var body: some View {
        HStack(spacing: Space.m) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { VColor.ink2.opacity(0.15) }
            }
            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.mediaType == .video ? "Video, \(DurationFormatting.string(seconds: asset.duration))" : "Photo").font(.subheadline)
                Text("\(asset.creationDate.map { DayTimeFormatting.string($0) } ?? "") · about \(ByteFormatting.string(PhotoCleanupModel.estimate(asset)))")
                    .font(.caption).foregroundStyle(VColor.ink2)
            }
        }
        .task {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 96, height: 96), contentMode: .aspectFill, options: opts) { img, _ in
                Task { @MainActor in image = img }
            }
        }
    }
}

import SwiftUI
import Photos
import VitalsKit
import VitalsDesign

/// "Vitals does it": photo and video clean-up (plan §5.14a). Permission is asked only when the person opens
/// this screen. Everything is analysed on the phone. Nothing is marked for the person: they look at items
/// (the viewer plays videos and zooms photos) and mark them. Deletion goes through the system confirmation into
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
    }

    var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var groups: [Group] = []
    /// One item, one state: an asset that sits in two groups (a screen recording that is also one of the largest
    /// videos) shares this one mark, and the totals count it once.
    var marked: Set<String> = []
    var scanning = false
    var deleting = false
    var lastResult: String?

    /// Every asset found, once each, so totals and Review never count an item twice.
    private var assetsByID: [String: PHAsset] = [:]

    var markedAssets: [PHAsset] {
        // In the order they appear on screen, first appearance only.
        var seen = Set<String>()
        return groups.flatMap(\.assets).filter { marked.contains($0.localIdentifier) && seen.insert($0.localIdentifier).inserted }
    }
    var markedBytes: Double { marked.compactMap { assetsByID[$0] }.map(Self.estimate).reduce(0, +) }

    func isMarked(_ a: PHAsset) -> Bool { marked.contains(a.localIdentifier) }
    func setMarked(_ a: PHAsset, _ on: Bool) {
        if on { marked.insert(a.localIdentifier) } else { marked.remove(a.localIdentifier) }
    }
    func toggle(_ a: PHAsset) { setMarked(a, !isMarked(a)) }

    func requestAndScan() async {
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited else { return }
        scanning = true
        defer { scanning = false }
        let found = await Task.detached(priority: .userInitiated) { Self.scan() }.value
        groups = found
        assetsByID = Dictionary(found.flatMap(\.assets).map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        marked = marked.filter { assetsByID[$0] != nil }   // drop marks for items that are gone
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
        func g(_ id: String, _ t: String, _ w: String, _ a: [PHAsset]) -> Group { Group(id: id, title: t, why: w, assets: a) }
        return [
            g("dupes", "Likely duplicates", "Same size and length, taken in the same second as another item, which stays.", duplicates),
            g("bursts", "Extra burst shots", "Burst photos other than the one chosen as the burst's best.", Array(burstExtras)),
            g("screenshots", "Screenshots older than 30 days", "Usually kept by accident.", screenshots),
            g("recordings", "Screen recordings", "Often large and rarely rewatched.", recordings),
            g("videos", "Largest videos", "Open each one to watch it before you decide.", Array(bigVideos)),
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

    func deleteMarked(model: AppModel) async {
        let ids = marked
        guard !ids.isEmpty else { return }
        deleting = true
        defer { deleting = false }
        let before = await model.snapshot()
        do {
            try await Self.deleteAssets(Array(ids))
            marked = []
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

    // MARK: Words for one item (VoiceOver and the viewer)

    nonisolated static func kind(_ a: PHAsset) -> String {
        if a.mediaType == .video { return a.mediaSubtypes.contains(.videoScreenRecording) ? "Screen recording" : "Video" }
        return a.mediaSubtypes.contains(.photoScreenshot) ? "Screenshot" : "Photo"
    }

    /// "1 minute 4 seconds": spoken length for VoiceOver.
    nonisolated static func spokenDuration(_ seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute, .second] : [.second]
        f.unitsStyle = .full
        f.maximumUnitCount = 2
        return f.string(from: seconds.rounded()) ?? "\(Int(seconds)) seconds"
    }

    /// "0:42", "12:05": the badge on video thumbnails, as Photos shows it.
    nonisolated static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    nonisolated static func dateText(_ a: PHAsset) -> String { a.creationDate.map { DayTimeFormatting.string($0) } ?? "Date unknown" }

    /// "Video, 1 minute, Yesterday 10:02 PM, about 18.9 MB, marked for deletion"
    nonisolated static func accessibilityLabel(_ a: PHAsset, marked: Bool) -> String {
        var parts = [kind(a)]
        if a.mediaType == .video { parts.append(spokenDuration(a.duration)) }
        parts.append(dateText(a))
        parts.append("about \(ByteFormatting.string(estimate(a)))")
        if marked { parts.append("marked for deletion") }
        return parts.joined(separator: ", ")
    }
}

/// Opens the viewer on a list of items at one of them.
struct ViewerRequest: Identifiable {
    let id = UUID()
    let assets: [PHAsset]
    let start: Int
}

struct PhotoCleanupView: View {
    @Environment(AppModel.self) private var model
    @State private var cleanup = PhotoCleanupModel()
    @State private var viewer: ViewerRequest?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                Text("Vitals looks through your library on this phone and suggests what to delete. Tap an item to look at it or play it, and mark what should go. Nothing goes until you confirm, and deleted items stay in Recently Deleted for 30 days.")
                    .font(.subheadline).foregroundStyle(VColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                content
                if let r = cleanup.lastResult {
                    VStack(alignment: .leading, spacing: Space.s) {
                        SectionTitle("Result")
                        Label(r, systemImage: "checkmark.circle").foregroundStyle(VColor.ink)
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.l)
        }
        .safeAreaInset(edge: .bottom) {
            if !cleanup.groups.isEmpty { SelectionBar(cleanup: cleanup, review: review) }
        }
        .vitalsGround()
        .navigationTitle("Photos clean-up")
        .fullScreenCover(item: $viewer) { r in
            PhotoViewer(cleanup: cleanup, assets: r.assets, start: r.start)
                .environment(model)
        }
        .task { if cleanup.status == .authorized || cleanup.status == .limited { await cleanup.requestAndScan() } }
    }

    @ViewBuilder private var content: some View {
        switch cleanup.status {
        case .notDetermined:
            Button("Allow Photos access and scan") { Task { await cleanup.requestAndScan() } }.vitalsButton(.primary)
        case .denied, .restricted:
            Text("Photos access is off. Settings > Apps > Vitals > Photos to allow it.").foregroundStyle(VColor.attention)
        default:
            if cleanup.scanning && cleanup.groups.isEmpty { HStack { ProgressView(); Text("Scanning on this phone…") } }
            if cleanup.groups.isEmpty && !cleanup.scanning {
                Text("Nothing obvious to clean up.").foregroundStyle(VColor.ink2)
            }
            ForEach(cleanup.groups) { g in
                GroupGrid(group: g, cleanup: cleanup) { i in
                    viewer = ViewerRequest(assets: g.assets, start: i)
                }
            }
        }
    }

    private func review() {
        let items = cleanup.markedAssets
        guard !items.isEmpty else { return }
        viewer = ViewerRequest(assets: items, start: 0)
    }
}

private struct GroupGrid: View {
    let group: PhotoCleanupModel.Group
    let cleanup: PhotoCleanupModel
    let open: (Int) -> Void
    /// 3 across on the closed Duo, more when it is open: each cell at least 104 pt.
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Space.xs)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionTitle("\(group.title) · \(group.assets.count)")
            Text(group.why).font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: columns, spacing: Space.m) {
                ForEach(Array(group.assets.enumerated()), id: \.element.localIdentifier) { i, a in
                    AssetCell(asset: a, cleanup: cleanup) { open(i) }
                }
            }
        }
    }
}

/// A thumbnail like Photos: tap to open, a round check in the corner to mark, a duration badge on videos and the
/// estimated size underneath.
private struct AssetCell: View {
    let asset: PHAsset
    let cleanup: PhotoCleanupModel
    let open: () -> Void
    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let marked = cleanup.isMarked(asset)
        VStack(alignment: .leading, spacing: Space.xs) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image { Image(uiImage: image).resizable().scaledToFill() } else { VColor.ink2.opacity(0.15) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if asset.mediaType == .video {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                                Text(PhotoCleanupModel.clock(asset.duration)).font(.caption2.weight(.semibold)).monospacedDigit()
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                        }
                    }
                    .overlay { if marked { Color.black.opacity(0.25) } }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay { if marked { RoundedRectangle(cornerRadius: 10).strokeBorder(VColor.problem, lineWidth: 3) } }
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture(perform: open)
                // A sibling, not an overlay of the open action, so a tap on the check marks and does not open.
                Button { cleanup.toggle(asset) } label: { MarkCheck(marked: marked) }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)   // the cell's own action does this for VoiceOver
            }
            Text("about \(ByteFormatting.string(PhotoCleanupModel.estimate(asset)))")
                .font(.caption2).foregroundStyle(marked ? VColor.problem : VColor.ink2)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PhotoCleanupModel.accessibilityLabel(asset, marked: marked))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens it to look at or play.")
        .accessibilityAction { open() }
        .accessibilityAction(named: marked ? "Unmark" : "Mark for deletion") { cleanup.toggle(asset) }
        .task(id: asset.localIdentifier) {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            opts.resizeMode = .fast
            let side = 140 * scale
            Thumbnails.manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: opts) { img, _ in
                Task { @MainActor in if let img { image = img } }
            }
        }
    }
}

enum Thumbnails {
    @MainActor static let manager = PHCachingImageManager()
}

/// The round check in a thumbnail's corner. Empty ring when not marked; filled problem colour with a check when
/// marked for deletion. 44 pt hit area.
struct MarkCheck: View {
    var marked: Bool
    var body: some View {
        ZStack {
            Circle().fill(marked ? AnyShapeStyle(VColor.problem) : AnyShapeStyle(.black.opacity(0.2)))
            Circle().strokeBorder(.white, lineWidth: 1.5)
            if marked { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.3), radius: 2)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

/// The bar that stays at the bottom: what is marked, its estimated size, Review and Delete.
struct SelectionBar: View {
    let cleanup: PhotoCleanupModel
    let review: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let n = cleanup.marked.count
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(n == 0 ? "Nothing marked" : "\(n) marked").font(.headline).foregroundStyle(VColor.ink)
                if n > 0 { Text("about \(ByteFormatting.string(cleanup.markedBytes))").font(.caption).foregroundStyle(VColor.ink2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Review", action: review).vitalsButton(.secondary, size: .regular).disabled(n == 0)
            Button(role: .destructive) { Task { await cleanup.deleteMarked(model: model) } } label: {
                Text("Delete").foregroundStyle(n == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(VColor.problem))
            }
            .vitalsButton(.destructive, size: .regular)
            .disabled(n == 0 || cleanup.deleting)
            .accessibilityLabel(n == 0 ? "Delete" : "Delete \(n) marked")
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .background(.bar)
        .overlay(alignment: .top) { VColor.hairline.frame(height: 0.5) }
    }
}

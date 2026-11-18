import SwiftUI
import Photos
import AVKit
import VitalsKit
import VitalsDesign

/// Full-screen look at the clean-up items before deciding: a pager through one group (or through the marked
/// items, from Review). Photos zoom; videos play inline, starting muted with a visible unmute button. Items kept
/// only in iCloud download on demand with progress. Keep and Delete at the bottom only MARK the item (Delete
/// marks it, nothing is deleted here) and move on to the next. On a wide screen (the open Duo) the media sits on
/// one side and the details and actions on the other.
struct PhotoViewer: View {
    let cleanup: PhotoCleanupModel
    let assets: [PHAsset]
    /// The page on screen; bound to the pager's scroll position so the start item really is the first shown.
    @State private var current: Int?
    private var index: Int { current ?? 0 }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionLevel) private var motion

    init(cleanup: PhotoCleanupModel, assets: [PHAsset], start: Int) {
        self.cleanup = cleanup
        self.assets = assets
        _current = State(initialValue: min(max(start, 0), max(assets.count - 1, 0)))
    }

    var body: some View {
        GeometryReader { geo in
            // Side by side whenever the space is landscape and wide enough for media plus a 300 pt panel
            // (the open Duo, or the closed Duo turned sideways, whose side strip leaves about 595 pt).
            let wide = geo.size.width >= 540 && geo.size.width > geo.size.height
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                if wide {
                    HStack(spacing: 0) {
                        pager.id("\(Int(geo.size.width))x\(Int(geo.size.height))")   // rebuilt at the current item after a resize, so no page is left half in view
                        details.frame(width: min(360, geo.size.width * 0.36)).frame(maxHeight: .infinity, alignment: .bottom)
                            .background(VColor.surface)
                    }
                } else {
                    VStack(spacing: 0) {
                        pager.id("\(Int(geo.size.width))x\(Int(geo.size.height))")   // rebuilt at the current item after a resize, so no page is left half in view
                        details.background(VColor.surface)
                    }
                }
                topBar
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(false)
    }

    /// A paging scroll view rather than a page-style TabView: the TabView ignored the start index and opened on
    /// the last item.
    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(assets.enumerated()), id: \.offset) { i, a in
                    SwiftUI.Group {
                        if a.mediaType == .video { VideoPage(asset: a, isCurrent: i == index) } else { PhotoPage(asset: a) }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.black.opacity(0.35), in: Circle())
            .accessibilityLabel("Close")
            Spacer()
            Text("\(index + 1) of \(assets.count)")
                .font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background(.black.opacity(0.35), in: Capsule())
        }
        .padding(.horizontal, Space.l).padding(.top, Space.s)
    }

    @ViewBuilder private var details: some View {
        if assets.indices.contains(index) {
            let a = assets[index]
            let marked = cleanup.isMarked(a)
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PhotoCleanupModel.dateText(a)).font(.headline).foregroundStyle(VColor.ink)
                        Text(subtitle(a)).font(.subheadline).foregroundStyle(VColor.ink2)
                    }
                    Spacer()
                    if marked {
                        Label("Marked", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(VColor.problem)
                    }
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: Space.m) {
                    Button { decide(a, delete: false) } label: { Text("Keep").frame(maxWidth: .infinity) }
                        .vitalsButton(.secondary)
                    Button(role: .destructive) { decide(a, delete: true) } label: { Text("Delete").foregroundStyle(VColor.problem).frame(maxWidth: .infinity) }
                        .vitalsButton(.destructive)
                        .accessibilityHint("Marks it for deletion. Nothing is deleted until you confirm from the list.")
                }
                Text("Delete only marks it. Marked items go together from the list, after the system asks you.")
                    .font(.caption).foregroundStyle(VColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
        }
    }

    private func subtitle(_ a: PHAsset) -> String {
        var parts = [PhotoCleanupModel.kind(a)]
        if a.mediaType == .video { parts.append(DurationFormatting.string(seconds: a.duration)) }
        parts.append("about \(ByteFormatting.string(PhotoCleanupModel.estimate(a)))")
        return parts.joined(separator: " · ")
    }

    /// Mark (or unmark) and move to the next item; past the last one, close.
    private func decide(_ a: PHAsset, delete: Bool) {
        cleanup.setMarked(a, delete)
        if index + 1 < assets.count {
            withAnimation(motion == .still ? nil : Motion.settle) { current = index + 1 }
        } else {
            dismiss()
        }
    }
}

// MARK: Photo

private struct PhotoPage: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var progress: Double?
    @State private var failed = false
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            if let image { ZoomableImage(image: image).accessibilityLabel(PhotoCleanupModel.kind(asset)) }
            DownloadState(progress: progress, failed: failed, loaded: image != nil)
        }
        .task(id: asset.localIdentifier) { await load() }
    }

    private func load() async {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.progressHandler = { p, _, _, _ in Task { @MainActor in progress = p < 1 ? p : nil } }
        let target = CGSize(width: 1600 * scale / 2, height: 1600 * scale / 2)
        PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: opts) { img, info in
            let error = info?[PHImageErrorKey] != nil
            Task { @MainActor in
                if let img { image = img; if !(info?[PHImageResultIsDegradedKey] as? Bool ?? false) { progress = nil } }
                else if error { failed = true; progress = nil }
            }
        }
    }
}

/// Pinch and double-tap to zoom, as in Photos.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let s = UIScrollView()
        s.minimumZoomScale = 1
        s.maximumZoomScale = 5
        s.showsVerticalScrollIndicator = false
        s.showsHorizontalScrollIndicator = false
        s.delegate = context.coordinator
        s.backgroundColor = .clear
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isAccessibilityElement = false
        s.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalTo: s.frameLayoutGuide.widthAnchor),
            iv.heightAnchor.constraint(equalTo: s.frameLayoutGuide.heightAnchor),
            iv.topAnchor.constraint(equalTo: s.contentLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: s.contentLayoutGuide.bottomAnchor),
            iv.leadingAnchor.constraint(equalTo: s.contentLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: s.contentLayoutGuide.trailingAnchor),
        ])
        context.coordinator.imageView = iv
        let dt = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        dt.numberOfTapsRequired = 2
        s.addGestureRecognizer(dt)
        return s
    }

    func updateUIView(_ s: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image { context.coordinator.imageView?.image = image }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let s = g.view as? UIScrollView else { return }
            let animate = !UIAccessibility.isReduceMotionEnabled
            if s.zoomScale > 1 { s.setZoomScale(1, animated: animate); return }
            let p = g.location(in: imageView)
            let size = CGSize(width: s.bounds.width / 2.5, height: s.bounds.height / 2.5)
            s.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: animate)
        }
    }
}

// MARK: Video

/// PhotoKit hands the player item back on its own queue; it is used only on the main actor after that.
private struct PlayerItemBox: @unchecked Sendable { let item: AVPlayerItem }

private struct VideoPage: View {
    let asset: PHAsset
    let isCurrent: Bool
    @State private var player: AVPlayer?
    @State private var poster: UIImage?
    @State private var progress: Double?
    @State private var failed = false
    @State private var muted = true

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else if let poster {
                Image(uiImage: poster).resizable().scaledToFit().accessibilityHidden(true)
            }
            DownloadState(progress: progress, failed: failed, loaded: player != nil)
        }
        .overlay(alignment: .topTrailing) {
            if player != nil {
                Button {
                    muted.toggle()
                    player?.isMuted = muted
                } label: {
                    Label(muted ? "Unmute" : "Mute", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.m).frame(minHeight: 44)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 60).padding(.trailing, Space.l)   // below the counter
                .accessibilityLabel(muted ? "Unmute video" : "Mute video")
            }
        }
        .task(id: asset.localIdentifier) { await load() }
        .onChange(of: isCurrent) { _, now in now ? player?.play() : player?.pause() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        let po = PHImageRequestOptions()
        po.deliveryMode = .opportunistic
        po.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1200, height: 1200), contentMode: .aspectFit, options: po) { img, _ in
            Task { @MainActor in if let img { poster = img } }
        }
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .automatic
        opts.progressHandler = { p, _, _, _ in Task { @MainActor in progress = p < 1 ? p : nil } }
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: opts) { item, info in
            let box = item.map(PlayerItemBox.init)
            let error = info?[PHImageErrorKey] != nil
            Task { @MainActor in
                progress = nil
                guard let box else { _ = error; failed = true; return }
                let p = AVPlayer(playerItem: box.item)
                p.isMuted = muted
                player = p
                if isCurrent { p.play() }
            }
        }
    }
}

/// iCloud download progress, or why the item could not be shown.
private struct DownloadState: View {
    var progress: Double?
    var failed: Bool
    var loaded: Bool
    var body: some View {
        if failed && !loaded {
            Label("Could not load this item. It may be in iCloud and the phone is offline.", systemImage: "icloud.slash")
                .font(.subheadline).foregroundStyle(.white).padding(Space.l)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                .padding(Space.l)
        } else if let progress {
            VStack(spacing: Space.s) {
                ProgressView(value: progress).tint(.white).frame(width: 180)
                Text("Downloading from iCloud · \(Int(progress * 100)) %").font(.caption).foregroundStyle(.white)
            }
            .padding(Space.l)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
        } else if !loaded {
            ProgressView().tint(.white)
        }
    }
}

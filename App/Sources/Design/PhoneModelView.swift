import SwiftUI
import VitalsKit
import VitalsDesign

/// The hero (plan section 6): the phone drawn as a model you can see into. Each region is one area of
/// the check-up, labelled with its icon and name, coloured and shaped by its status, and a button into
/// that area. While scanning, a sweep runs down the phone and each region lights as its probe finishes.
/// On iPhone Duo it is drawn as a Duo: closed, open with a crease, or partly open, following the hinge.
///
/// Drawing: the body, sweep and arrival glow are a Canvas; the regions are real views (labels, buttons,
/// accessibility). Continuous redraw only while something moves; none under Reduce Motion.
struct PhoneModelView: View {
    var scan: ScanState
    var results: Checkup?
    var isDuo: Bool
    var onSelect: ((Area) -> Void)? = nil

    @Environment(\.motionLevel) private var motion
    @Environment(\.hinge) private var hinge
    @State private var arrivals: [Area: Date] = [:]
    @State private var appeared = Date.distantPast

    private var animating: Bool {
        guard motion.allowsContinuous else { return false }
        if scan.phase == .running { return true }
        let now = Date()
        if isDuo && now.timeIntervalSince(appeared) < 1.2 { return true }
        return arrivals.values.contains { now.timeIntervalSince($0) < 1.0 }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: motion.frameInterval, paused: !animating)) { context in
            GeometryReader { geo in
                let g = Geometry(size: geo.size, unfold: unfold(at: context.date), isDuo: isDuo, shortSide: DeviceShape.shortOverLong)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in drawBody(&ctx, g: g, now: context.date) }
                    ForEach(g.regions, id: \.area) { r in
                        RegionTile(area: r.area, status: status(r.area), scanning: scan.phase == .running && scan.finished[r.area] == nil,
                                   compact: r.rect.height < 76, fade: 1, onSelect: onSelect)
                            .frame(width: r.rect.width, height: r.rect.height)
                            .offset(x: r.rect.minX, y: r.rect.minY)
                    }
                }
            }
        }
        .onAppear { appeared = .now }
        .onChange(of: scan.finished) { old, new in
            for area in new.keys where old[area] == nil { arrivals[area] = .now }
            if new.isEmpty { arrivals = [:] }
        }
    }

    private func status(_ area: Area) -> Status? {
        scan.finished[area] ?? (scan.phase == .running ? nil : results?.result(for: area)?.status)
    }

    /// 0 closed … 1 fully open. Follows the hinge when the system reports one; opens on first appearance otherwise.
    /// `-duoOpen` forces the open drawing (the Simulator reports the hinge closed).
    private func unfold(at now: Date) -> Double {
        guard isDuo else { return 0 }
        var u = 1.0
        if motion == .full {
            let t = min(1, max(0, now.timeIntervalSince(appeared) / 0.9))
            u = 1 - pow(1 - t, 3)
        }
        if ProcessInfo.processInfo.arguments.contains("-duoOpen") { return u }
        if let hinge {
            switch hinge.status {
            case .closed: u = 0
            case .partiallyOpen: u = min(u, max(0.15, (hinge.angle ?? 90) / 180))
            default: break
            }
        }
        return u
    }

    // MARK: Geometry

    struct Region { let area: Area; let rect: CGRect }

    /// One device body. An ordinary iPhone: a tall body with the Dynamic Island. iPhone Duo closed: the outer
    /// display's wider, shorter body with the camera in a corner. Open: one wide body (the inner display) with a
    /// fine crease down the centre and no camera showing; partly open, the same body narrows with the hinge.
    /// Proportions come from the screen the app is running on (`shortSide` = short edge ÷ long edge): on a Duo the
    /// outer display and the inner display are the same rectangle turned, so one measurement gives both shapes.
    struct Geometry {
        let body: CGRect
        let corner: CGFloat
        let foldX: CGFloat?
        let unfold: Double
        let island: CGRect?
        let camera: CGRect?
        let regions: [Region]

        init(size: CGSize, unfold: Double, isDuo: Bool, shortSide: CGFloat) {
            let closedAspect = shortSide                       // width ÷ height when closed / ordinary iPhone
            let openAspect = 1 / max(shortSide, 0.1)           // the inner display, turned
            let open = isDuo && unfold > 0.02
            let aspect = isDuo ? closedAspect + (openAspect - closedAspect) * CGFloat(unfold) : closedAspect
            let h = min(size.height, size.width / aspect)
            let w = h * aspect
            body = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
            corner = min(w, h) * 0.13
            self.unfold = unfold
            foldX = open ? body.midX : nil
            island = isDuo ? nil : CGRect(x: body.midX - w * 0.14, y: body.minY + h * 0.022, width: w * 0.28, height: h * 0.026)
            let cam = min(w, h) * 0.055
            camera = isDuo && !open ? CGRect(x: body.maxX - corner * 0.55 - cam, y: body.minY + corner * 0.45, width: cam, height: cam) : nil

            if open, let fx = foldX {
                // Two sides of the crease; nothing straddles it.
                let gap = max(6, w * 0.012)
                let left = CGRect(x: body.minX, y: body.minY, width: fx - gap - body.minX, height: h)
                let right = CGRect(x: fx + gap, y: body.minY, width: body.maxX - fx - gap, height: h)
                regions = PhoneModelView.layout(open: true).map { area, side, u in
                    let r = side == 0 ? left : right
                    return Region(area: area, rect: CGRect(x: r.minX + u.minX * r.width, y: r.minY + u.minY * r.height,
                                                           width: u.width * r.width, height: u.height * r.height))
                }
            } else {
                let b = body
                regions = PhoneModelView.layout(open: false).map { area, _, u in
                    Region(area: area, rect: CGRect(x: b.minX + u.minX * b.width, y: b.minY + u.minY * b.height,
                                                    width: u.width * b.width, height: u.height * b.height))
                }
            }
        }
    }

    /// Region rects in unit space: of the whole body (closed, ordinary iPhone), or of one side of the crease (open).
    nonisolated static func layout(open: Bool) -> [(Area, Int, CGRect)] {
        if open {
            return [
                (.network, 0, CGRect(x: 0.10, y: 0.08, width: 0.84, height: 0.15)),
                (.heat, 0, CGRect(x: 0.10, y: 0.27, width: 0.84, height: 0.36)),
                (.memory, 0, CGRect(x: 0.10, y: 0.67, width: 0.84, height: 0.25)),
                (.storage, 1, CGRect(x: 0.06, y: 0.08, width: 0.84, height: 0.22)),
                (.battery, 1, CGRect(x: 0.06, y: 0.34, width: 0.84, height: 0.38)),
                (.software, 1, CGRect(x: 0.06, y: 0.77, width: 0.84, height: 0.15)),
            ]
        }
        return [
            (.network, 0, CGRect(x: 0.07, y: 0.075, width: 0.86, height: 0.095)),
            (.heat, 0, CGRect(x: 0.07, y: 0.19, width: 0.42, height: 0.25)),
            (.memory, 0, CGRect(x: 0.51, y: 0.19, width: 0.42, height: 0.25)),
            (.storage, 0, CGRect(x: 0.07, y: 0.46, width: 0.86, height: 0.13)),
            (.battery, 0, CGRect(x: 0.07, y: 0.61, width: 0.86, height: 0.21)),
            (.software, 0, CGRect(x: 0.07, y: 0.84, width: 0.86, height: 0.095)),
        ]
    }

    // MARK: Drawing

    private func drawBody(_ ctx: inout GraphicsContext, g: Geometry, now: Date) {
        let shape = RoundedRectangle(cornerRadius: g.corner, style: .continuous).path(in: g.body)
        ctx.fill(shape, with: .color(VColor.surface))
        if let fx = g.foldX {
            // The crease: a soft shadow either side and one fine line. Partly open, the far side is a touch darker.
            var crease = ctx
            crease.clip(to: shape)
            let shade = g.body.width * 0.05
            crease.fill(Path(CGRect(x: fx - shade, y: g.body.minY, width: shade * 2, height: g.body.height)),
                        with: .linearGradient(Gradient(colors: [.clear, VColor.ink.opacity(0.07), .clear]),
                                              startPoint: CGPoint(x: fx - shade, y: 0), endPoint: CGPoint(x: fx + shade, y: 0)))
            if g.unfold < 0.95 {
                crease.fill(Path(CGRect(x: fx, y: g.body.minY, width: g.body.maxX - fx, height: g.body.height)),
                            with: .color(VColor.ink.opacity(0.06 * (1 - g.unfold))))
            }
            crease.stroke(Path { p in p.move(to: CGPoint(x: fx, y: g.body.minY + 2)); p.addLine(to: CGPoint(x: fx, y: g.body.maxY - 2)) },
                          with: .color(VColor.ink2.opacity(0.45)), lineWidth: 1)
        }
        // The outline is always ink: status lives in the regions, not the frame.
        ctx.stroke(shape, with: .color(VColor.ink.opacity(0.85)), lineWidth: 2.5)
        if let island = g.island { ctx.fill(Capsule().path(in: island), with: .color(VColor.ink.opacity(0.8))) }
        if let cam = g.camera { ctx.fill(Circle().path(in: cam), with: .color(VColor.ink.opacity(0.8))) }

        // Arrival glow: a brief bloom when a region's reading lands.
        if motion == .full {
            for r in g.regions {
                guard let at = arrivals[r.area], let s = status(r.area) else { continue }
                let k = max(0, 1 - now.timeIntervalSince(at) / 0.9)
                guard k > 0 else { continue }
                var glow = ctx
                glow.addFilter(.blur(radius: 12 * k))
                glow.stroke(RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: r.rect),
                            with: .color(VColor.status(s).opacity(k)), lineWidth: 8 * k)
            }
        }
        // Sweep while scanning, across the whole body.
        if scan.phase == .running && motion.allowsContinuous {
            let period = 1.4
            let t = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let b = g.body
            let y = b.minY + b.height * (0.03 + 0.94 * t)
            var sweep = ctx
            sweep.clip(to: shape)
            sweep.fill(Path(CGRect(x: b.minX, y: y - 22, width: b.width, height: 44)),
                       with: .linearGradient(Gradient(colors: [VColor.fine.opacity(0), VColor.fine.opacity(0.3), VColor.fine.opacity(0)]),
                                             startPoint: CGPoint(x: 0, y: y - 22), endPoint: CGPoint(x: 0, y: y + 22)))
            sweep.fill(Path(CGRect(x: b.minX + 6, y: y - 1, width: max(0, b.width - 12), height: 2)), with: .color(VColor.fine))
        }
    }
}

/// The shape of the device Vitals is running on, from its screen: short edge ÷ long edge. An iPhone Duo's outer
/// and inner displays are the same rectangle turned, so this one number gives both the closed and the open shape.
@MainActor
enum DeviceShape {
    static var shortOverLong: CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let s = scene?.screen.bounds.size ?? CGSize(width: 440, height: 956)
        guard s.width > 0, s.height > 0 else { return 0.46 }
        return min(s.width, s.height) / max(s.width, s.height)
    }
}

/// One area on the phone: icon, name, status shape. A button into the area when `onSelect` is set.
private struct RegionTile: View {
    var area: Area
    var status: Status?
    var scanning: Bool
    var compact: Bool
    var fade: Double
    var onSelect: ((Area) -> Void)?
    @Environment(\.motionLevel) private var motion

    var body: some View {
        let tint = status.map { VColor.status($0) } ?? VColor.ink2
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button { onSelect?(area) } label: {
            ZStack {
                shape.fill(status == nil ? Color.clear : tint.opacity(0.14))
                shape.strokeBorder(status == nil ? VColor.ink2.opacity(0.45) : tint,
                                   style: StrokeStyle(lineWidth: status == nil ? 1 : 1.5, dash: scanning ? [4, 3] : []))
                content(tint: tint)
                    .padding(.horizontal, 4)
            }
            .contentShape(shape)
        }
        .buttonStyle(RegionPress())
        .disabled(onSelect == nil)
        .opacity(fade)
        .animation(Motion.change(motion, Motion.settle), value: status)
        .accessibilityLabel(area.title)
        .accessibilityValue(scanning ? "Reading" : status?.label ?? "Not checked yet")
        .accessibilityHint(onSelect == nil ? "" : "Shows the readings for \(area.title.lowercased())")
    }

    @ViewBuilder private func content(tint: Color) -> some View {
        let ink = status == nil ? VColor.ink2 : VColor.ink
        // Largest that fits: icon, name and status; then icon and status only (the name stays in the label).
        ViewThatFits {
            if compact {
                HStack(spacing: 5) {
                    Image(systemName: area.symbol).font(.caption.weight(.semibold))
                    Text(area.shortTitle).font(.caption.weight(.semibold)).lineLimit(1)
                    if let status { StatusMark(status, size: 9) }
                }
                .foregroundStyle(ink)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: area.symbol).font(.title3.weight(.medium)).foregroundStyle(status == nil ? VColor.ink2 : tint)
                    Text(area.shortTitle).font(.caption.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
                    if let status { StatusMark(status, size: 10) }
                }
                .padding(.vertical, 8)   // the mark never touches the tile's edge; too short → the row layout below
            }
            HStack(spacing: 5) {
                Image(systemName: area.symbol).font(.caption.weight(.semibold))
                Text(area.shortTitle).font(.caption.weight(.semibold)).lineLimit(1)
                if let status { StatusMark(status, size: 9) }
            }
            .foregroundStyle(ink)
            HStack(spacing: 4) {
                Image(systemName: area.symbol).font(.caption.weight(.semibold)).foregroundStyle(ink)
                if let status { StatusMark(status, size: 9) }
            }
        }
    }
}

private struct RegionPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

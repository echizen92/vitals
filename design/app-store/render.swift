// Renders the App Store slides (1320 × 2868, Apple's 6.9" size) from simulator captures.
// Usage: swift design/app-store/render.swift   (run from the repo root)
// Captions and order follow design/app-store/README.md. One caption = one idea; the real screen proves it.
import AppKit

let W: CGFloat = 1320, H: CGFloat = 2868
let paper = NSColor(red: 0xF4/255, green: 0xF1/255, blue: 0xEA/255, alpha: 1)
let ink = NSColor(red: 0x0B/255, green: 0x0F/255, blue: 0x14/255, alpha: 1)
let ink2 = NSColor(red: 0x55/255, green: 0x5B/255, blue: 0x62/255, alpha: 1)
let mint = NSColor(red: 0x0A/255, green: 0x74/255, blue: 0x62/255, alpha: 1)

let slides: [(String, String, String, String)] = [
    ("01-checkup",    "Find out why your\niPhone runs hot",     "One check-up names the problem",        "01-checkup"),
    ("02-causes",     "See which apps\nwere busy",              "Matched to each hot spell",              "02-hot-spell"),
    ("03-what-to-do", "Steps that\nactually help",              "Then Vitals checks if they worked",      "03-what-to-do"),
    ("04-heat",       "Your phone's day,\nin heat",             "Heat level and battery, side by side",   "04-heat"),
    ("05-relief",     "Quick relief,\nno fake boosts",          "Clean up photos, cool down, restart",    "05-relief"),
    ("06-private",    "Nothing leaves\nyour phone",             "No account, no tracking. Open source.",  "06-private"),
]

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineSpacing = size * 0.04
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    return NSAttributedString(string: s, attributes: [.font: rounded, .foregroundColor: color, .paragraphStyle: p, .kern: -size * 0.01])
}

let root = URL(fileURLWithPath: "design/app-store")
for (name, title, sub, screen) in slides {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    paper.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    // Caption block (AppKit's origin is bottom-left).
    let t = text(title, size: 112, weight: .bold, color: ink)
    let tb = t.boundingRect(with: NSSize(width: W - 160, height: 600), options: [.usesLineFragmentOrigin])
    t.draw(with: NSRect(x: 80, y: H - 200 - tb.height, width: W - 160, height: tb.height), options: [.usesLineFragmentOrigin])
    let s = text(sub, size: 54, weight: .medium, color: ink2)
    let sb = s.boundingRect(with: NSSize(width: W - 160, height: 200), options: [.usesLineFragmentOrigin])
    s.draw(with: NSRect(x: 80, y: H - 236 - tb.height - sb.height, width: W - 160, height: sb.height), options: [.usesLineFragmentOrigin])
    // A short mint rule: the brand's "fine" colour, used once.
    mint.setFill(); NSBezierPath(roundedRect: NSRect(x: W / 2 - 40, y: H - 140, width: 80, height: 10), xRadius: 5, yRadius: 5).fill()
    // The real screen, framed like a device, bleeding off the bottom edge.
    let img = NSImage(contentsOf: root.appendingPathComponent("source/screens/\(screen).png"))!
    let sw: CGFloat = 1040, sh = sw * img.size.height / img.size.width
    let top = H - 300 - tb.height - sb.height
    let frame = NSRect(x: (W - sw) / 2, y: top - sh, width: sw, height: sh)
    let bezel = frame.insetBy(dx: -22, dy: -22)
    let shadow = NSShadow(); shadow.shadowColor = ink.withAlphaComponent(0.18); shadow.shadowBlurRadius = 60; shadow.shadowOffset = NSSize(width: 0, height: -20)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    ink.setFill(); NSBezierPath(roundedRect: bezel, xRadius: 150, yRadius: 150).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: frame, xRadius: 130, yRadius: 130).addClip()
    img.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    // App Store wants no alpha channel: flatten to RGB.
    let cg = rep.cgImage!
    let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! out.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("iphone-6.9/\(name).png"))
    print("✓ iphone-6.9/\(name).png")
}

// Renders the Vitals app icon (light, dark, tinted) at 1024 px with CoreGraphics.
// SUPERSEDED: the shipped icon is design/logo/vitals-icon-1024.png. Do not run over the asset catalogue.
// The mark: the outline of a phone you can see into, crossed by one pulse line, the scan.
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let size = 1024.0

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(ground: UInt32?, outline: UInt32, pulse: UInt32, glow: UInt32, file: String) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let ground {
        ctx.setFillColor(rgb(ground)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        // A faint cool field behind the phone.
        let g = CGGradient(colorsSpace: cs, colors: [rgb(glow, 0.35), rgb(glow, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 520), startRadius: 0, endCenter: CGPoint(x: 512, y: 520), endRadius: 470, options: [])
    }
    // Phone outline.
    let phone = CGRect(x: 512 - 190, y: 512 - 330, width: 380, height: 660)
    let path = CGPath(roundedRect: phone, cornerWidth: 92, cornerHeight: 92, transform: nil)
    ctx.addPath(path); ctx.setStrokeColor(rgb(outline)); ctx.setLineWidth(30); ctx.strokePath()
    // Camera island.
    ctx.addPath(CGPath(roundedRect: CGRect(x: 512 - 60, y: phone.maxY - 82, width: 120, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.setFillColor(rgb(outline)); ctx.fillPath()
    // Pulse: flat, one beat, flat. Extends past the phone on both sides.
    let y = 500.0
    let pts: [CGPoint] = [CGPoint(x: 150, y: y), CGPoint(x: 400, y: y), CGPoint(x: 450, y: y + 70), CGPoint(x: 512, y: y - 170),
                          CGPoint(x: 572, y: y + 120), CGPoint(x: 618, y: y), CGPoint(x: 874, y: y)]
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addLines(between: pts); ctx.setStrokeColor(rgb(pulse)); ctx.setLineWidth(34); ctx.strokePath()
    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appendingPathComponent(file))
}

// Superseded by design/logo/vitals-icon-1024.png (chosen by the maintainer). Kept for reference.
render(ground: 0xF4F2EC, outline: 0x111416, pulse: 0x0B7263, glow: 0x6CD6C3, file: "AppIcon.png")
render(ground: 0x0B0D0E, outline: 0xEDEBE5, pulse: 0x6CD6C3, glow: 0x2F6F66, file: "AppIcon-Dark.png")
render(ground: 0x000000, outline: 0xBDBDBD, pulse: 0xFFFFFF, glow: 0x333333, file: "AppIcon-Tinted.png")
print("icons written to \(out)")

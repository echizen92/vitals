// Renders the Vitals mark (phone with the pulse through it, from design/logo/vitals-icon.svg geometry)
// on a transparent background for the launch screen, in a light-mode and a dark-mode colour.
// Usage: swift scripts/make-launch-mark.swift <out-dir>
import AppKit

func render(outline: NSColor, to url: URL, px: CGFloat) {
    let s = px / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let g = NSGraphicsContext.current!.cgContext
    g.translateBy(x: 0, y: px); g.scaleBy(x: s, y: -s)       // SVG coordinates
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: 120, y: 516)); pulse.addLine(to: CGPoint(x: 432, y: 516)); pulse.addLine(to: CGPoint(x: 492, y: 372))
    pulse.addLine(to: CGPoint(x: 556, y: 612)); pulse.addLine(to: CGPoint(x: 604, y: 516)); pulse.addLine(to: CGPoint(x: 904, y: 516))
    // Phone outline with gaps where the pulse crosses it.
    g.saveGState()
    g.addRect(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    g.addPath(pulse.copy(strokingWithWidth: 64, lineCap: .butt, lineJoin: .round, miterLimit: 10))
    g.clip(using: .evenOdd)
    g.setStrokeColor(outline.cgColor); g.setLineWidth(30)
    g.addPath(CGPath(roundedRect: CGRect(x: 318, y: 186, width: 388, height: 652), cornerWidth: 78, cornerHeight: 78, transform: nil))
    g.strokePath()
    g.restoreGState()
    // Pulse with the warm-to-mint gradient.
    g.saveGState()
    g.addPath(pulse.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10)); g.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let colors = [0xFFB347, 0xFF6B5E, 0x3FD6B8, 0x3FD6B8].map { NSColor(red: CGFloat($0 >> 16 & 255) / 255, green: CGFloat($0 >> 8 & 255) / 255, blue: CGFloat($0 & 255) / 255, alpha: 1).cgColor }
    let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 0.2, 0.46, 1])!
    g.drawLinearGradient(grad, start: CGPoint(x: 0, y: 372), end: CGPoint(x: 0, y: 620), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    g.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
for (suffix, scale) in [("", 1.0), ("@2x", 2.0), ("@3x", 3.0)] {
    render(outline: NSColor(red: 0x0B / 255, green: 0x0F / 255, blue: 0x14 / 255, alpha: 1), to: out.appendingPathComponent("launch-mark\(suffix).png"), px: 200 * scale)
    render(outline: NSColor(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xEA / 255, alpha: 1), to: out.appendingPathComponent("launch-mark-dark\(suffix).png"), px: 200 * scale)
}

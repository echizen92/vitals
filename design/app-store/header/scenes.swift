// Vitals App Store header, 3840 x 1646 (21:9), 12 s seamless loop at 30 fps, 90 BPM (18 beats).
// The app icon's idea on the full canvas: one mint pulse line runs across the page; the phone outline from the
// icon sits in the art safe area (1646 x 661 at x 1097, y 493) with a real app screen inside. Every 6 beats a
// light travels along the line; when it reaches the phone the spike flares in the heat colours and the screen
// and caption change: check-up, the busy apps of a hot spell, the heat timeline. Everything is periodic in 12 s.
import AppKit

INK = 0x0B0F14; PAPER = 0xF4F1EA
let MINTL: UInt32 = 0x3FD6B8, FAIR: UInt32 = 0xFFB347, SERIOUS: UInt32 = 0xFF8F52, CRIT: UInt32 = 0xFF6B5E

let SHOTS = [load("assets/01-checkup.png"), load("assets/02-hot-spell.png"), load("assets/04-heat.png")]
let CAPS: [[String]] = [["Find out why your", "iPhone runs hot"], ["See which apps", "were busy"], ["Your phone's day,", "in heat"]]

// Safe area and layout
let SAFE = CGRect(x: 1097, y: 493, width: 1646, height: 661)
let PH: CGFloat = 640, PW: CGFloat = PH * 0.64
let PCX: CGFloat = 2390, PCY: CGFloat = CY
let LINE_Y: CGFloat = PCY + PH * 0.0
let STROKE: CGFloat = PH * 0.038
let PERIOD = 6.0, HIT = 3.0

// The pulse line: flat across the canvas with the icon's spike inside the phone (traced from the 1024 px icon).
func spikePts(_ amp: CGFloat) -> [CGPoint] {
    [CGPoint(x: PCX - PH * 0.14, y: LINE_Y),
     CGPoint(x: PCX - PH * 0.032, y: LINE_Y - PH * 0.243 * amp),
     CGPoint(x: PCX + PH * 0.065, y: LINE_Y + PH * 0.173 * amp),
     CGPoint(x: PCX + PH * 0.146, y: LINE_Y)]
}
func linePath(_ amp: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -200, y: LINE_Y))
    for q in spikePts(amp) { p.addLine(to: q) }
    p.addLine(to: CGPoint(x: FW + 200, y: LINE_Y))
    return p
}
func stroked(_ p: CGPath, _ w: CGFloat) -> CGPath { p.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 4) }

func render(_ t: Double, frame: Int) {
    let b = t / BEAT
    let loopPhase = t / DURATION                      // 0…1 over the whole loop
    let cyc = floor((b - HIT) / PERIOD)               // which hit we are after
    let idx = ((Int(cyc) % 3) + 3) % 3                // screen shown now
    let prev = (idx + 2) % 3
    let since = b - (HIT + cyc * PERIOD)              // beats since the last hit (0…6)
    let flare = exp(-since / 1.1)                     // decays after each hit
    let pre = since > 5.2 ? pr(since, 5.2, 0.8) : 0   // caption leaves just before the next hit

    // Background: ink, a cool glow on the left, a warm glow behind the phone that flares on each hit.
    fillRect(CGRect(x: 0, y: 0, width: FW, height: FH), C(INK))
    let breathe = 0.5 + 0.5 * sin(2 * .pi * loopPhase)
    radial(CGPoint(x: 900, y: FH * 0.7), 1500, [C(MINTL, 0.07 + 0.02 * breathe), C(MINTL, 0)])
    radial(CGPoint(x: PCX, y: PCY), 1200 + 120 * CGFloat(flare), [C(SERIOUS, 0.10 + 0.16 * flare), C(FAIR, 0.04), C(FAIR, 0)], [0, 0.45, 1])

    // Atmosphere for the wide edges: a faint heat strip (the app's timeline colours) drifting once per loop.
    save {
        let segs: [UInt32] = [MINTL, MINTL, FAIR, MINTL, MINTL, MINTL, SERIOUS, FAIR, MINTL, MINTL, FAIR, MINTL]
        let sw: CGFloat = 320, total = sw * CGFloat(segs.count), off = CGFloat(loopPhase) * total
        let y = LINE_Y + 470
        var x = -off
        while x < FW {
            for (k, c) in segs.enumerated() {
                let r = CGRect(x: x + CGFloat(k) * sw + 6, y: y, width: sw - 12, height: 14)
                if r.maxX > 0 && r.minX < FW { fill(rr(r, 7), C(c, 0.13)) }
            }
            x += total
        }
    }

    ctx.saveGState()
    scaleAbout(CX, CY, CGFloat(1 + 0.004 * sin(2 * .pi * loopPhase)))

    let amp = CGFloat(1 + 0.18 * flare)

    // Base line, dim, behind the phone.
    fill(stroked(linePath(amp), STROKE), C(MINTL, 0.32))

    // Travelling light: head off-canvas at both ends of each period, centred on the phone at the hit.
    let ph = (b - cyc * PERIOD - HIT) / PERIOD + 0.5  // 0.5 at the hit
    let p01 = ph - floor(ph)
    let hx = PCX + CGFloat(p01 - 0.5) * 6700
    save {
        ctx.addPath(CGPath(rect: CGRect(x: hx - 1100, y: 0, width: 1100, height: FH), transform: nil)); ctx.clip()
        linear(stroked(linePath(amp), STROKE), [C(MINTL, 0), C(MINTL, 0.95)], CGPoint(x: hx - 1100, y: 0), CGPoint(x: hx, y: 0))
    }
    radial(CGPoint(x: hx, y: LINE_Y), 120, [C(0xE8FFF8, 0.55), C(MINTL, 0.18), C(MINTL, 0)], [0, 0.35, 1])

    // Phone outline with the app screen inside.
    let outer = CGRect(x: PCX - PW / 2, y: PCY - PH / 2, width: PW, height: PH)
    let rad = PH * 0.12
    let inner = outer.insetBy(dx: STROKE * 1.45, dy: STROKE * 1.45)
    save {
        ctx.addPath(rr(inner, rad - STROKE * 1.45)); ctx.clip()
        fillRect(inner, C(PAPER))
        func shot(_ i: Int, _ a: CGFloat) {
            let im = SHOTS[i]
            let w = inner.width, h = w * CGFloat(im.height) / CGFloat(im.width)
            img(im, CGRect(x: inner.minX, y: inner.minY - h * 0.035, width: w, height: h), alpha: a)
        }
        let x = oCubic(pr(since, 0, 0.9))
        if x < 1 { shot(prev, 1) }
        if x > 0 { save { scaleAbout(inner.midX, inner.midY, CGFloat(1.04 - 0.04 * x)); shot(idx, CGFloat(x)) } }
        // A soft band of ink behind the spike so the line reads over the screen.
        linear(nil, [C(INK, 0), C(INK, 0.55), C(INK, 0)], CGPoint(x: 0, y: LINE_Y - PH * 0.3), CGPoint(x: 0, y: LINE_Y + PH * 0.24), [0, 0.5, 1])
    }
    save {
        ctx.setShadow(offset: .zero, blur: 40, color: C(PAPER, 0.25))
        fill(stroked(rr(outer, rad), STROKE), C(PAPER))
    }

    // The spike on top, in the icon's heat gradient, brighter on each hit.
    let sp = CGMutablePath(); let pts = spikePts(amp)
    sp.move(to: CGPoint(x: outer.minX - 30, y: LINE_Y)); for q in pts { sp.addLine(to: q) }; sp.addLine(to: CGPoint(x: outer.maxX + 30, y: LINE_Y))
    fill(stroked(sp, STROKE), C(MINTL))
    let peak = CGMutablePath(); peak.move(to: pts[0]); peak.addLine(to: pts[1]); peak.addLine(to: pts[2])
    save {
        ctx.setShadow(offset: .zero, blur: 30 + 50 * CGFloat(flare), color: C(SERIOUS, 0.5 + 0.4 * flare))
        linear(stroked(peak, STROKE * 1.02), [C(CRIT), C(FAIR), C(MINTL)], CGPoint(x: 0, y: pts[1].y), CGPoint(x: 0, y: LINE_Y + 20), [0, 0.45, 1])
    }

    // Caption, left of the phone, inside the safe area.
    let f = font(92, .bold)
    let capX = outer.minX - 110
    func caption(_ i: Int, _ a: Double, _ rise: Double) {
        guard a > 0.001 else { return }
        for (k, line) in CAPS[i].enumerated() {
            let y = PCY - 14 + CGFloat(k) * 112 + CGFloat(rise) * 30
            text(line, f, capX, y, align: 1, .solid(C(PAPER)), kern: -1.5, alpha: CGFloat(a))
        }
    }
    let inA = oCubic(pr(since, 0.2, 0.8)), inA2 = oCubic(pr(since, 0.45, 0.8))
    if since < 0.2 { caption(prev, 0, 0) }
    save {
        // first line then second line, each rising into place
        for (k, line) in CAPS[idx].enumerated() {
            let a = (k == 0 ? inA : inA2) * (1 - ioCubic(pre))
            guard a > 0.001 else { continue }
            let y = LINE_Y - 172 + CGFloat(k) * 112 + CGFloat(1 - (k == 0 ? inA : inA2)) * 30
            text(line, f, capX, y, align: 1, .solid(C(PAPER)), kern: -1.5, alpha: CGFloat(a))
        }
    }
    ctx.restoreGState()
    finish(frame: frame, t: t, vignetteStrength: 0.25)
}

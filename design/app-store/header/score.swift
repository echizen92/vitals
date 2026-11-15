// Vitals header loop: calm, 90 BPM, 18 beats = 12.0 s, D major. Muted by default on the App Store, so the
// picture carries everything; this is a quiet bed for people who unmute. No fade, so the loop joins cleanly.
// Every 6 beats the pulse reaches the phone (beats 3, 9, 15): a soft heartbeat (lub-dub) and a bell.
MIX.sidechainDepth = 0.12; MIX.sidechainRelease = 0.2; MIX.reverbWet = 1.1; MIX.drive = 1.2; MIX.ceiling = 0.85
MIX.delayBeats = 1.5; MIX.delayFeedback = 0.3; MIX.fadeStart = 12.5

let chords: [[Double]] = [[50, 57, 61, 64, 66], [47, 54, 57, 62, 64], [43, 50, 54, 59, 62]]   // Dmaj9, Bm9, Gmaj9
let bells: [Double] = [78, 74, 81]
for k in 0..<3 {
    let b0 = Double(k) * 6
    for (i, m) in chords[k].enumerated() {
        ep(bt(b0) + Double(i) * 0.03, m, bt(6) - 0.05, i == 0 ? 0.32 : 0.2, pan: -0.3 + 0.15 * Double(i))
    }
    sub(bt(b0), chords[k][0] - 12, bt(6) - 0.1, 0.22)
    softKick(bt(b0 + 3), 0.55)
    softKick(bt(b0 + 3.4), 0.3)
    bell(bt(b0 + 3), bells[k], 0.22, pan: 0.15)
    for e in stride(from: 0.0, to: 6.0, by: 0.5) where Int(e * 2) % 2 == 1 {
        shaker(bt(b0 + e), 0.07, pan: 0.35)
    }
}

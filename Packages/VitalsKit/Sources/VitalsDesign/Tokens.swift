import SwiftUI
import VitalsKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Vitals' identity: a calm clinical instrument.
// Near-black and paper-white grounds, one cool accent that means "fine", a warm ramp for heat,
// and status colours that always travel with a shape. Values are tuned for WCAG AA against both
// grounds (see Docs/M11-accessibility.md for the measured ratios).

extension Color {
    /// A colour that switches with the appearance.
    public init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) })
        #endif
    }

    public init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
#endif

/// The palette. Hex values are listed so they can be checked for contrast outside the app.
public enum Palette {
    // Aligned with the app icon (design/logo): ink #0B0F14, paper #F4F1EA, mint #3FD6B8 for "fine",
    // heat ramp #FFB347 → #FF6B5E. Mint and the ramp are too light for text on paper, so light mode uses
    // darker text tones of the same hues. All text pairs measured ≥ 4.5:1 (Docs/M11-accessibility.md).
    public static let groundLight: UInt32 = 0xF4F1EA, groundDark: UInt32 = 0x0B0F14
    public static let surfaceLight: UInt32 = 0xFFFFFF, surfaceDark: UInt32 = 0x161B21
    public static let inkLight: UInt32 = 0x0B0F14, inkDark: UInt32 = 0xF4F1EA
    public static let ink2Light: UInt32 = 0x555B62, ink2Dark: UInt32 = 0x9DA3AA
    public static let fineLight: UInt32 = 0x0A7462, fineDark: UInt32 = 0x3FD6B8
    public static let attentionLight: UInt32 = 0x8F5A00, attentionDark: UInt32 = 0xFFB347
    public static let problemLight: UInt32 = 0xB3362B, problemDark: UInt32 = 0xFF6B5E
    public static let unknownLight: UInt32 = 0x62686E, unknownDark: UInt32 = 0x8C9298
    // Heat ramp, cool to hot, from the icon's pulse gradient. Fills only; text uses the status tones.
    public static let heatNominal: UInt32 = 0x3FD6B8, heatFair: UInt32 = 0xFFB347, heatSerious: UInt32 = 0xFF8F52, heatCritical: UInt32 = 0xFF6B5E
}

public enum VColor {
    public static let ground = Color(light: Palette.groundLight, dark: Palette.groundDark)
    public static let surface = Color(light: Palette.surfaceLight, dark: Palette.surfaceDark)
    public static let ink = Color(light: Palette.inkLight, dark: Palette.inkDark)
    public static let ink2 = Color(light: Palette.ink2Light, dark: Palette.ink2Dark)
    public static let hairline = Color(light: 0xDEDAD0, dark: 0x2A3038)
    public static let fine = Color(light: Palette.fineLight, dark: Palette.fineDark)
    public static let attention = Color(light: Palette.attentionLight, dark: Palette.attentionDark)
    public static let problem = Color(light: Palette.problemLight, dark: Palette.problemDark)
    public static let unknown = Color(light: Palette.unknownLight, dark: Palette.unknownDark)

    public static func status(_ s: Status) -> Color {
        switch s {
        case .good, .expected: fine
        case .attention: attention
        case .problem: problem
        case .unknown: unknown
        }
    }

    public static func heat(_ t: ThermalLevel) -> Color {
        switch t {
        case .nominal: Color(hex: Palette.heatNominal)
        case .fair: Color(hex: Palette.heatFair)
        case .serious: Color(hex: Palette.heatSerious)
        case .critical: Color(hex: Palette.heatCritical)
        }
    }

    /// Heat colour as text: the ramp is too light for text on paper, so text uses the status tones.
    public static func heatText(_ t: ThermalLevel) -> Color {
        switch t {
        case .nominal: fine
        case .fair: attention
        case .serious, .critical: problem
        }
    }
}

public enum VFont {
    /// Large numerals: rounded, monospaced digits so values do not jitter as they change.
    public static func numeral(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
    public static let title = Font.system(.title2, design: .default, weight: .semibold)
    public static let headline = Font.headline
    public static let body = Font.body
    public static let caption = Font.caption
    /// Raw evidence and log text.
    public static let mono = Font.system(.footnote, design: .monospaced)
}

public enum Space {
    public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 36
    public static let corner: CGFloat = 22
}

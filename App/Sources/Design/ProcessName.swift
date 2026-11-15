import SwiftUI
import VitalsKit
import VitalsDesign

/// Friendly process names everywhere a process is shown: "iCloud Drive" first, `bird` second,
/// the glossary's one-line explanation as the accessibility hint. Unknown processes show their raw name.
enum ProcessNames {
    static func friendly(_ raw: String) -> (name: String, raw: String?, what: String?) {
        let short = ProcessGlossary.shortName(raw)
        if let e = ProcessGlossary.entry(for: raw) { return (e.name, short, e.what) }
        return (short, nil, nil)
    }

    /// "iCloud Drive (bird)" for places that only take a string (titles, spoken labels).
    static func label(_ raw: String) -> String {
        let f = friendly(raw)
        return f.raw.map { "\(f.name) (\($0))" } ?? f.name
    }
}

struct ProcessName: View {
    var raw: String
    var font: Font = .headline
    var rawOnNewLine = false

    var body: some View {
        let f = ProcessNames.friendly(raw)
        let layout = rawOnNewLine ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            Text(f.name).font(font).foregroundStyle(VColor.ink)
            if let r = f.raw { Text(r).font(.caption).foregroundStyle(VColor.ink2) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(f.name)
        .accessibilityHint(f.what ?? "")
    }
}

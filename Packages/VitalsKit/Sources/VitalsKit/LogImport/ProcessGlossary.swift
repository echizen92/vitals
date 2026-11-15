import Foundation

/// Plain-language names for system processes (bundled, no network).
public enum ProcessGlossary {
    public struct Entry: Decodable, Sendable, Hashable {
        public let name: String
        public let group: String
        public let what: String
        public let adviceKey: String?
    }
    struct File: Decodable { let processes: [String: Entry] }

    static let table: [String: Entry] = {
        guard let url = Bundle.module.url(forResource: "process-glossary", withExtension: "json"),
              let data = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return f.processes
    }()

    /// "com.apple.cloudd" → "cloudd"; "/usr/libexec/bird" → "bird"; widget extensions keep their name.
    public static func shortName(_ raw: String) -> String {
        var s = raw
        if let slash = s.lastIndex(of: "/") { s = String(s[s.index(after: slash)...]) }
        if s.hasPrefix("com.apple.") { s = String(s.dropFirst("com.apple.".count)) }
        return s
    }

    public static func entry(for raw: String) -> Entry? {
        let s = shortName(raw)
        if let e = table[s] { return e }
        if s.hasSuffix("WidgetExtension") || s.hasSuffix("Widget") {
            return Entry(name: "A widget (\(s))", group: "widget", what: "A Home or Lock Screen widget refreshing its content.", adviceKey: "widget.cpu")
        }
        return nil
    }

    /// "iCloud Drive", or the short raw name when the glossary does not know it. For sentences.
    public static func friendlyName(_ raw: String) -> String {
        entry(for: raw)?.name ?? shortName(raw)
    }

    /// "iCloud Drive (bird)" or the raw name when unknown.
    public static func display(_ raw: String) -> String {
        let s = shortName(raw)
        if let e = entry(for: s) { return "\(e.name) (\(s))" }
        return s
    }

    public static func processes(inGroup group: String) -> [String] {
        table.filter { $0.value.group == group }.map(\.key).sorted()
    }
}

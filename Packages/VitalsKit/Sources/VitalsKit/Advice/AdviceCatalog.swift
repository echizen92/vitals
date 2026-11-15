import Foundation

/// The bundled advice catalogue (plan §5.14). No network; updates ship with app updates.
public enum AdviceCatalog {
    public enum Relief: String, Codable, Sendable, CaseIterable {
        case vitals, shortcut, guided, manual
        public var label: String {
            switch self {
            case .vitals: "Vitals does it"
            case .shortcut: "One tap through Shortcuts"
            case .guided: "Guided, under a minute"
            case .manual: "You do it in Settings"
            }
        }
    }

    public struct Action: Codable, Sendable, Hashable, Identifiable {
        public var id: String = ""
        public let title: String
        public let why: String
        public let steps: [String]
        public let effect: String
        public let downside: String
        public let effort: String
        public let relief: Relief
        public let watch: WatchMetric
        public let source: String
        enum CodingKeys: String, CodingKey { case title, why, steps, effect, downside, effort, relief, watch, source }
    }

    public struct Entry: Codable, Sendable, Hashable {
        public let actions: [String]
        public let escalation: [String]
        public let safety: String?
    }

    struct File: Decodable {
        let version: Int
        let asOf: String
        let actions: [String: Action]
        let findings: [String: Entry]
        let myths: [String: String]
    }

    static let file: File? = {
        guard let url = Bundle.module.url(forResource: "advice", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    public static var version: Int { file?.version ?? 0 }
    public static var asOf: String { file?.asOf ?? "" }
    public static var allActionIDs: [String] { (file?.actions.keys).map { Array($0).sorted() } ?? [] }
    public static var allFindingKeys: [String] { (file?.findings.keys).map { Array($0).sorted() } ?? [] }

    public static func action(_ id: String) -> Action? {
        guard var a = file?.actions[id] else { return nil }
        a.id = id
        return a
    }

    public static func entry(for key: String) -> Entry? { file?.findings[key] }

    /// One to three actions, in catalogue order (by likely effect and effort).
    public static func actions(for finding: Finding) -> [Action] {
        (entry(for: finding.resolvedAdviceKey)?.actions ?? []).prefix(3).compactMap(action)
    }

    public static func escalation(for key: String) -> [Action] {
        (entry(for: key)?.escalation ?? []).compactMap(action)
    }

    public static func safety(for key: String) -> Action? { entry(for: key)?.safety.flatMap(action) }

    public static func myth(_ key: String) -> String? { file?.myths[key] }
}

import Foundation

/// Reads text recognised (on-device, Vision) from a screenshot of Settings > Battery or Battery Health
/// (plan §4a item 3). Per-app battery share exists only on that screen. The person confirms every value
/// before it is used; values are labelled "Read from screenshot".
/// UNVERIFIED: recognition quality and the screen's exact layout on iOS 27.2; parsing is tolerant.
public enum BatteryScreenshotParser {
    public struct AppShare: Codable, Sendable, Hashable, Identifiable {
        public var app: String
        public var percent: Int
        public var id: String { app }
        public init(app: String, percent: Int) { self.app = app; self.percent = percent }
    }

    public struct Result: Codable, Sendable, Hashable {
        public var apps: [AppShare]
        public var maximumCapacity: Int?
        public var periodLabel: String?
    }

    static let ignore: Set<String> = ["battery", "battery health", "battery level", "activity", "screen on", "screen off", "show activity",
                                      "last 24 hours", "last 10 days", "low power mode", "battery usage by app", "insights and suggestions"]

    /// `lines`: recognised text in reading order (top to bottom, left to right).
    public static func parse(_ lines: [String]) -> Result {
        var apps: [AppShare] = []
        var maxCap: Int?
        var period: String?
        var pendingName: String?
        let clean = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, line) in clean.enumerated() {
            let lower = line.lowercased()
            if lower.contains("maximum capacity") {
                if let p = percent(in: line) ?? clean.dropFirst(i + 1).first.flatMap(percent(in:)) { maxCap = p }
                continue
            }
            if lower.hasPrefix("last 24 hours") || lower.hasPrefix("last 10 days") || lower.range(of: #"^\d{1,2}(:\d{2})?\s*(am|pm)?\s*[–-]"#, options: .regularExpression) != nil {
                period = period ?? line
            }
            // "Safari 23%" on one line, or the name on one line and "23%" on the next.
            if let p = percent(in: line) {
                let name = line.replacingOccurrences(of: #"\s*\d{1,3}\s?%.*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                let app = name.isEmpty ? pendingName : name
                if let app, !ignore.contains(app.lowercased()), (0...100).contains(p), app.count < 40 {
                    if !apps.contains(where: { $0.app == app }) { apps.append(AppShare(app: app, percent: p)) }
                }
                pendingName = nil
            } else if !ignore.contains(lower), line.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil, line.count < 40,
                      !lower.contains("min") || lower.contains("minecraft") {
                pendingName = line
            }
        }
        return Result(apps: apps, maximumCapacity: maxCap, periodLabel: period)
    }

    static func percent(in s: String) -> Int? {
        guard let r = s.range(of: #"(\d{1,3})\s?%"#, options: .regularExpression) else { return nil }
        return Int(s[r].filter(\.isNumber))
    }
}

import Foundation

/// Paths and defaults shared by the app, widgets and share extension through the app group.
public enum SharedContainer {
    public static let appGroup = "group.sg.com.vitals.app"

    /// The group container, or a folder in Application Support when the group is not available
    /// (unit tests on the Mac, or a build without the entitlement). The fallback keeps the app usable
    /// but means widgets cannot see the data; `isUsingGroup` tells the settings screen which one is live.
    public static var url: URL {
        if let override = overrideURL { return override }
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VitalsShared", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static var isUsingGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    /// Tests point this at a temporary folder.
    nonisolated(unsafe) public static var overrideURL: URL?

    public static var databaseURL: URL { url.appendingPathComponent("vitals.sqlite") }
    public static var snapshotURL: URL { url.appendingPathComponent("latest-checkup.json") }

    /// Files the share extension dropped off; the app moves them into its own imports folder on next launch.
    public static var inboxURL: URL {
        let u = url.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

/// Counts memory-pressure warnings Vitals receives while it runs. iOS sends these to the app that is
/// short of memory, so this is a narrow view: it shows pressure Vitals itself felt, not the whole phone.
public enum MemoryWarningCounter {
    private static let countKey = "memoryWarnings.count"
    private static let sinceKey = "memoryWarnings.since"

    public static func record(now: Date = .now) {
        let d = SharedContainer.defaults
        if d.object(forKey: sinceKey) == nil { d.set(now, forKey: sinceKey) }
        d.set(d.integer(forKey: countKey) + 1, forKey: countKey)
        d.set(now, forKey: "memoryWarnings.last")
    }

    public static func startCountingIfNeeded(now: Date = .now) {
        let d = SharedContainer.defaults
        if d.object(forKey: sinceKey) == nil { d.set(now, forKey: sinceKey) }
    }

    public static var count: Int { SharedContainer.defaults.integer(forKey: countKey) }
    public static var since: Date? { SharedContainer.defaults.object(forKey: sinceKey) as? Date }
}

import Foundation
import VitalsKit

/// Imported originals are copied into the app's own container (Application Support/Imports), where the
/// person can delete them. A sysdiagnose is not copied whole (hundreds of MB); the reports found inside it are.
enum ImportLibrary {
    static var folder: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Imports", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func deleteAllFiles() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func url(for record: ImportRecord) -> URL? {
        record.storedPath.map { folder.appendingPathComponent($0) }
    }

    static func delete(_ record: ImportRecord) {
        let dir = folder.appendingPathComponent(record.id, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Reads, parses and keeps a shared file. Runs off the main actor; large archives stream.
    static func ingest(url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> ImportResult {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let id = LogImporter.stableID(name: url.lastPathComponent, size: size)
            var result = try LogImporter.importFile(at: url, id: id, progress: progress)
            let dir = folder.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if result.record.kind == .sysdiagnose {
                let reports = dir.appendingPathComponent("reports", isDirectory: true)
                try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
                for (i, f) in result.extractedFiles.enumerated() {
                    try f.data.write(to: reports.appendingPathComponent("\(i)-\(f.name)"))
                }
                result.record.storedPath = "\(id)/reports"
                result.record.notes.append("The archive itself was not kept; its \(result.extractedFiles.count) reports were.")
            } else {
                let dest = dir.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: dest)
                result.record.storedPath = "\(id)/\(url.lastPathComponent)"
            }
            result.extractedFiles = []
            return result
        }.value
    }

    /// Raw text for an event's source file (for "view the raw report").
    static func rawText(for event: LogEvent, record: ImportRecord?) -> String? {
        guard let record, let url = url(for: record) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue { return readCapped(url) }
        // Sysdiagnose: events carry "<importID>/<index>#…" ids; find the matching extracted report.
        let index = event.id.split(separator: "/").dropFirst().first.map { $0.prefix { $0 != "#" } }.map(String.init)
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        if let index, let match = files.first(where: { $0.lastPathComponent.hasPrefix("\(index)-") }) { return readCapped(match) }
        return nil
    }

    static func readCapped(_ url: URL, limit: Int = 400_000) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: limit)) ?? Data()
        var s = String(decoding: data, as: UTF8.self)
        if data.count == limit { s += "\n\n… (truncated at \(limit / 1000) KB)" }
        return s
    }

    /// Files dropped off by the share extension.
    static func inboxFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: SharedContainer.inboxURL, includingPropertiesForKeys: nil))?
            .filter { !$0.lastPathComponent.hasPrefix(".") } ?? []
    }
}

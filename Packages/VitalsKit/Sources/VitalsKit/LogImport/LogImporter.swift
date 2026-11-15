import Foundation

/// What one shared file turned into.
public struct ImportResult: Sendable {
    public var record: ImportRecord
    public var events: [LogEvent]
    public var batteryHealth: BatteryHealth?
    /// The daily summary when the file is a daily analytics file (or a sysdiagnose holding one).
    public var analyticsDays: [AnalyticsDay] = []
    /// Samples from a Mac companion capture (with battery temperature), added to the heat timeline.
    public var samples: [Sample]
    public var processSamples: [VitalsReport.ProcessSample]
    public var processRates: [ProcessRate] = []
    public var processTotals: [ProcessTotal] = []
    /// For a sysdiagnose: the .ips files found inside, kept so their raw text can be shown.
    public var extractedFiles: [(name: String, data: Data)]
}

public enum LogImporter {
    public enum ImportError: Error, CustomStringConvertible {
        case unreadable(String), tooLarge
        public var description: String {
            switch self {
            case .unreadable(let s): "Vitals could not read this file: \(s)"
            case .tooLarge: "This file is too large to read as text. If it is a sysdiagnose, share the .tar.gz archive itself."
            }
        }
    }

    /// Text files over this size are refused (sysdiagnose archives are streamed separately).
    public static let maxTextBytes = 64 << 20

    public static func sniff(url: URL) -> ImportKind {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") || name.hasSuffix(".gz") { return .sysdiagnose }
        if name.hasSuffix(".vitalscapture") { return .companionCapture }
        // Peek at the first 4 KB only.
        guard let h = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 4096)) ?? Data()
        if head.starts(with: [0x1f, 0x8b]) { return .sysdiagnose }
        let text = String(decoding: head, as: UTF8.self)
        if text.contains("\"schemaVersion\"") && text.contains("\"generator\"") { return .companionCapture }
        let (header, body) = IPSParser.split(text)
        return IPSParser.classify(fileName: url.lastPathComponent, header: header, body: body)
    }

    /// Reads one file. `id` should be stable for the same file (e.g. a hash of name and size) so re-importing replaces it.
    public static func importFile(at url: URL, id: String, now: Date = .now, progress: ((Double) -> Void)? = nil) throws -> ImportResult {
        let kind = sniff(url: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let name = url.lastPathComponent
        var record = ImportRecord(id: id, fileName: name, kind: kind, importedAt: now, coversDate: nil, byteSize: size,
                                  storedPath: nil, eventCount: 0, notes: [])
        var result = ImportResult(record: record, events: [], batteryHealth: nil, samples: [], processSamples: [], extractedFiles: [])
        if name == "ota_patch.txt" {
            let text = String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
            result.events = otaEvents(text, importID: id, fileDate: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now)
            record.kind = .otherIPS
            record.coversDate = result.events.first?.timestamp
            record.notes.append(result.events.isEmpty ? "OS update log with no completed update found." : "OS update log: an update finished.")
            record.eventCount = result.events.count
            result.record = record
            return result
        }

        switch kind {
        case .sysdiagnose:
            return try importSysdiagnose(url: url, record: record, size: size, progress: progress)
        case .companionCapture:
            let data = try Data(contentsOf: url)
            let report = try JSON.decode(VitalsReport.self, data)
            record.coversDate = report.samples.first?.takenAt ?? report.generatedAt
            record.notes.append("\(report.samples.count) samples, \(report.processSamples?.count ?? 0) process samples from \(report.generator).")
            result.samples = report.samples.map { var s = $0; s.source = .companion; return s }
            result.processSamples = report.processSamples ?? []
            result.processRates = report.processRates ?? []
            result.processTotals = report.processTotals ?? []
            result.events = (report.events ?? []).map { var e = $0; e.importID = id; return e }
                + companionEvents(report.processSamples ?? [], importID: id)
            if report.samples.contains(where: { $0.thermalUnknown }) {
                record.notes.append("Battery temperature from the Mac; iOS's own thermal state is not visible to the Mac, so these points carry temperature only.")
            }
            if report.generator.contains("SIMULATED") { record.notes.append("This capture is SIMULATED data from the companion's test mode.") }
        default:
            guard size <= maxTextBytes else { throw ImportError.tooLarge }
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let parsed = parseText(text, fileName: name, kind: kind, importID: id, fallbackDate: now)
            result.events = parsed.events
            result.batteryHealth = parsed.health
            result.analyticsDays = parsed.day.map { [$0] } ?? []
            record.coversDate = parsed.date
            record.notes += parsed.notes
        }
        record.eventCount = result.events.count
        result.record = record
        return result
    }

    /// Live per-process CPU from a companion capture becomes events: the busiest minute per process,
    /// for processes at or above 20% CPU. These are measured on the Mac, so they rank strongly as culprits.
    static func companionEvents(_ ps: [VitalsReport.ProcessSample], importID: String, minPercent: Double = 20) -> [LogEvent] {
        var best: [String: VitalsReport.ProcessSample] = [:]
        for p in ps {
            guard let cpu = p.cpuPercent, cpu >= minPercent else { continue }
            let minute = Int(p.takenAt.timeIntervalSince1970 / 60)
            let key = "\(p.process)#\(minute)"
            if (best[key]?.cpuPercent ?? -1) < cpu { best[key] = p }
        }
        return best.sorted { $0.key < $1.key }.map { key, p in
            LogEvent(id: "\(importID)#cpu-\(key)", kind: .liveCPU, process: p.process, timestamp: p.takenAt,
                     magnitude: p.cpuPercent, magnitudeUnit: "% CPU", detail: "\(Int((p.cpuPercent ?? 0).rounded()))% CPU (Mac capture)", importID: importID)
        }
    }

    struct Parsed { var events: [LogEvent]; var health: BatteryHealth?; var date: Date?; var notes: [String]; var day: AnalyticsDay? = nil }

    /// `ota_patch.txt`: the update engine's log. A line containing "SUCCESS" marks a finished update; the
    /// lines carry only a time of day ("[13:46:00.0283-GMT]"), so the date comes from the file.
    static func otaEvents(_ text: String, importID: String, fileDate: Date) -> [LogEvent] {
        guard let line = text.split(separator: "\n").last(where: { $0.contains("SUCCESS") }) else { return [] }
        var ts = fileDate
        if let r = line.range(of: #"\[(\d{2}):(\d{2}):(\d{2})"#, options: .regularExpression) {
            let parts = line[r].dropFirst().split(separator: ":").compactMap { Int($0.prefix(2)) }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "GMT")!
            if parts.count == 3, let d = cal.date(bySettingHour: parts[0], minute: parts[1], second: parts[2], of: fileDate) {
                ts = d > fileDate.addingTimeInterval(3600) ? d.addingTimeInterval(-86_400) : d
            }
        }
        return [LogEvent(id: "\(importID)#ota", kind: .osUpdate, process: "iOS", timestamp: ts, detail: "update finished", importID: importID)]
    }

    static func parseText(_ text: String, fileName: String, kind: ImportKind, importID: String, fallbackDate: Date) -> Parsed {
        if kind == .analytics {
            let r = AnalyticsParser.parse(lines: text.split(separator: "\n", omittingEmptySubsequences: true), fileName: fileName,
                                          importID: importID, fallbackDate: fallbackDate)
            var notes = r.notes
            notes.insert("\(r.lineCount) lines read.", at: 0)
            if let h = r.health {
                notes.append("Battery values from keys: \(h.keysUsed.joined(separator: ", ")) (key names unverified).")
            }
            if let d = r.day {
                notes.append("\(d.recordCount) daily records. Times are not recorded in this file, so causes are matched to the day.")
            }
            return Parsed(events: r.events, health: r.health, date: r.coversDate, notes: notes, day: r.day)
        }
        let (header, body) = IPSParser.split(text)
        let date = header?.timestamp
        var events: [LogEvent]
        switch kind {
        case .crash: events = IPSParser.parseCrash(header: header, body: body, importID: importID, fallbackDate: fallbackDate)
        case .hang: events = IPSParser.parseHang(header: header, body: body, importID: importID, fallbackDate: fallbackDate)
        case .cpuResource, .wakeups, .diskWrites:
            events = IPSParser.parseResource(kind: kind, header: header, body: body, importID: importID, fallbackDate: fallbackDate)
        case .jetsam: events = IPSParser.parseJetsam(header: header, body: body, importID: importID, fallbackDate: fallbackDate)
        case .panic: events = IPSParser.parsePanic(header: header, body: body, importID: importID, fallbackDate: fallbackDate)
        default: events = []
        }
        var notes: [String] = []
        if [.cpuResource, .wakeups, .diskWrites, .hang, .panic].contains(kind) {
            notes.append("This report type's layout is not documented by Apple; Vitals reads it tolerantly (unverified).")
        }
        if kind == .otherIPS { notes.append("A system report Vitals does not interpret (bug_type \(header?.bugType ?? "?")). Kept for the report.") }
        if kind == .unknown { notes.append("Not a recognised iOS diagnostic file.") }
        return Parsed(events: events, health: nil, date: date ?? events.first?.timestamp, notes: notes)
    }

    static func importSysdiagnose(url: URL, record: ImportRecord, size: Int64, progress: ((Double) -> Void)?) throws -> ImportResult {
        var record = record
        var events: [LogEvent] = []
        var health: BatteryHealth?
        var extracted: [(String, Data)] = []
        var counts: [ImportKind: Int] = [:]
        var days: [AnalyticsDay] = []
        let reader = TarGzReader(url: url)
        let seen = try reader.read(want: { e in
            let p = e.path.lowercased()
            return (p.hasSuffix(".ips") || p.hasSuffix(".ips.ca.synced") || p.hasSuffix(".synced")) && e.size < 16 << 20
        }, found: { entry, data in
            let name = (entry.path as NSString).lastPathComponent
            let text = String(decoding: data, as: UTF8.self)
            let (h, b) = IPSParser.split(text)
            let kind = IPSParser.classify(fileName: name, header: h, body: b)
            counts[kind, default: 0] += 1
            let subID = "\(record.id)/\(extracted.count)"
            let parsed = parseText(text, fileName: name, kind: kind, importID: record.id, fallbackDate: record.importedAt)
            events += parsed.events.map { var e = $0; e.id = "\(subID)\(e.id.drop { $0 != "#" })"; return e }
            if let h = parsed.health, (health == nil || h.asOf > health!.asOf) { health = h }
            if let d = parsed.day { days.append(d) }
            if extracted.count < 2000 { extracted.append((name, data)) }
        }, progress: { read in progress?(size > 0 ? Double(read) / Double(size) : 0) })
        record.eventCount = events.count
        record.coversDate = events.map(\.timestamp).max()
        record.notes.append("Streamed \(seen) files from the archive; read \(extracted.count) reports.")
        let summary = counts.sorted { $0.value > $1.value }.map { "\($0.value) \($0.key.label.lowercased())" }.joined(separator: ", ")
        if !summary.isEmpty { record.notes.append(summary) }
        record.notes.append("Power and thermal logs inside a sysdiagnose are SQLite and binary formats Vitals does not read yet.")
        var result = ImportResult(record: record, events: events, batteryHealth: health, samples: [], processSamples: [], extractedFiles: extracted)
        result.analyticsDays = days
        return result
    }

    /// Files to import from a URL: the file itself, or every file inside a folder (recursively, so a copied
    /// crash-log folder with its `Retired/` subfolder imports in one go). Session analytics files are skipped:
    /// the daily file holds the useful records.
    public static func files(in url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return [url] }
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var out: [URL] = []
        while let u = e?.nextObject() as? URL {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let n = u.lastPathComponent
            if n.contains("session.ips.ca.synced") { continue }
            if n.hasSuffix(".ips") || n.hasSuffix(".synced") || n == "ota_patch.txt" || n.hasSuffix(".tar.gz") || n.hasSuffix(".vitalscapture") { out.append(u) }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Orders a batch so the newest daily analytics file is read first (plan §4a item 6).
    public static func ordered(_ urls: [URL]) -> [URL] {
        urls.sorted { a, b in
            let da = a.lastPathComponent.hasPrefix("Analytics-") && !a.lastPathComponent.contains("session")
            let db = b.lastPathComponent.hasPrefix("Analytics-") && !b.lastPathComponent.contains("session")
            if da != db { return da }
            return a.lastPathComponent > b.lastPathComponent
        }
    }

    /// A stable id from the name and size, so sharing the same file twice replaces the first import.
    public static func stableID(name: String, size: Int64) -> String {
        var hash: UInt64 = 1469598103934665603
        for b in "\(name)|\(size)".utf8 { hash = (hash ^ UInt64(b)) &* 1099511628211 }
        return String(hash, radix: 36)
    }
}

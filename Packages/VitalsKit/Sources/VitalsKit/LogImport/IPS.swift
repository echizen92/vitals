import Foundation

// iOS diagnostic reports (.ips).
//
// Documented by Apple ("Interpreting the JSON format of a crash report", "Identifying high-memory use with
// jetsam event reports"): an .ips file is one line of JSON metadata (`name`, `bug_type`, `bundleID`,
// `timestamp`, `os_version`, `incident_id`, …) followed by a body. For crashes (`bug_type` 309) the body is
// JSON with `procName`, `captureTime`, `exception`, `termination`. Jetsam reports have `date`, `largestProcess`,
// `memoryStatus.pageSize` and `processes[]` with `name`, `rpages`, `reason` (only on the jettisoned process).
//
// UNVERIFIED (plan §4, needs real files from the Duo): the body format of cpu_resource / wakeups / diskwrites
// reports (parsed here as the text "microstackshot" layout with `Command:`, `CPU:`, `Wakeups:`, `Writes:` lines),
// hang reports, panic reports and their bug_type numbers. Classification therefore trusts the file name first,
// then bug_type, then the body, and every parser tolerates missing keys.

public struct IPSHeader: Sendable, Hashable {
    public var raw: [String: String]
    public var name: String? { raw["name"] ?? raw["app_name"] ?? raw["procName"] }
    public var bugType: String? { raw["bug_type"] }
    public var bundleID: String? { raw["bundleID"] }
    public var osVersion: String? { raw["os_version"] }
    public var timestamp: Date? { raw["timestamp"].flatMap(IPSDate.parse) }
}

public enum IPSDate {
    /// "2026-11-14 10:22:33.00 +0800", with or without fractional seconds; ISO 8601 as a fallback.
    public static func parse(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        for format in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss.SSS Z", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: trimmed) { return d }
        }
        return ISO8601.parse(trimmed)
    }
}

public enum IPSParser {
    /// Splits an .ips file into its header line and body.
    public static func split(_ text: String) -> (header: IPSHeader?, body: String) {
        guard let nl = text.firstIndex(of: "\n") else {
            return (header(from: text), "")
        }
        let first = String(text[..<nl])
        let rest = String(text[text.index(after: nl)...])
        if let h = header(from: first) { return (h, rest) }
        return (nil, text)
    }

    static func header(from line: String) -> IPSHeader? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var flat: [String: String] = [:]
        for (k, v) in obj {
            switch v {
            case let s as String: flat[k] = s
            case let n as NSNumber: flat[k] = n.stringValue
            default: break
            }
        }
        return IPSHeader(raw: flat)
    }

    /// Classifies by file name first (most reliable for files shared from Analytics Data), then bug_type, then body.
    public static func classify(fileName: String, header: IPSHeader?, body: String) -> ImportKind {
        let n = fileName.lowercased()
        if n.hasPrefix("analytics-") || n.hasSuffix(".ips.ca.synced") || n.hasSuffix(".synced") { return .analytics }
        if n.contains("jetsamevent") { return .jetsam }
        if n.contains("cpu_resource") { return .cpuResource }
        if n.contains("wakeups_resource") { return .wakeups }
        if n.contains("diskwrites_resource") { return .diskWrites }
        if n.hasPrefix("panic") || n.hasPrefix("watchdog") { return .panic }
        if n == "ota_patch.txt" { return .otherIPS }
        if n.contains("hang") || n.contains(".spin") { return .hang }
        switch header?.bugType {
        case "309", "109": return .crash
        case "298": return .jetsam               // documented examples of JetsamEvent use 298 (unverified on iOS 27)
        case "210": return .panic                // unverified
        case "211": return .analytics            // unverified
        case "202": return .cpuResource          // microstackshot; unverified
        case "145": return .diskWrites           // confirmed on iOS 27.2.1 for *.diskwrites_resource
        case "409", "228": return .hang          // unverified
        default: break
        }
        if body.contains("\"largestProcess\"") { return .jetsam }
        if body.contains("Event:") && body.contains("cpu usage") { return .cpuResource }
        if body.contains("\"exception\"") || body.contains("Exception Type:") { return .crash }
        if header != nil { return .otherIPS }
        return .unknown
    }

    // MARK: Parsers

    public static func parseCrash(header: IPSHeader?, body: String, importID: String, fallbackDate: Date) -> [LogEvent] {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
        let process = (json?["procName"] as? String) ?? header?.name ?? "Unknown app"
        let date = (json?["captureTime"] as? String).flatMap(IPSDate.parse) ?? header?.timestamp ?? fallbackDate
        var detail: String?
        if let ex = json?["exception"] as? [String: Any] {
            detail = [ex["type"] as? String, ex["signal"] as? String].compactMap { $0 }.joined(separator: " ")
        } else if let r = body.range(of: #"Exception Type:\s*(.+)"#, options: .regularExpression) {
            detail = String(body[r]).replacingOccurrences(of: "Exception Type:", with: "").trimmingCharacters(in: .whitespaces)
        }
        if let term = json?["termination"] as? [String: Any], let ind = term["indicator"] as? String, !ind.isEmpty {
            detail = [detail, ind].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return [LogEvent(id: "\(importID)#0", kind: .crash, process: process, bundleID: header?.bundleID ?? (json?["bundleInfo"] as? [String: Any])?["CFBundleIdentifier"] as? String,
                         timestamp: date, detail: detail?.isEmpty == false ? detail : nil, importID: importID)]
    }

    public static func parseHang(header: IPSHeader?, body: String, importID: String, fallbackDate: Date) -> [LogEvent] {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
        let process = (json?["procName"] as? String) ?? header?.name ?? textField("Command", in: body) ?? "Unknown app"
        let duration = textField("Duration", in: body)
        return [LogEvent(id: "\(importID)#0", kind: .hang, process: process, bundleID: header?.bundleID, timestamp: header?.timestamp ?? fallbackDate,
                         detail: duration.map { "hung for \($0)" }, importID: importID)]
    }

    /// cpu_resource, wakeups_resource and diskwrites_resource (microstackshot text body). Unverified layout.
    public static func parseResource(kind: ImportKind, header: IPSHeader?, body: String, importID: String, fallbackDate: Date) -> [LogEvent] {
        let process = textField("Command", in: body) ?? header?.name ?? "Unknown process"
        let date = textField("End time", in: body).flatMap(IPSDate.parse) ?? textField("Date/Time", in: body).flatMap(IPSDate.parse)
            ?? header?.timestamp ?? fallbackDate
        var magnitude: Double?, unit: String?, detail: String?
        switch kind {
        case .cpuResource:
            // "CPU: 90 seconds cpu time over 104 seconds (87% cpu average), exceeding limit of 80% cpu over 180 seconds"
            if let line = textField("CPU", in: body) {
                detail = line
                let nums = numbers(in: line)
                if let first = nums.first { magnitude = first; unit = "CPU s" }
                if nums.count >= 2 { detail = "used \(Int(nums[0])) s of CPU in \(Int(nums[1])) s" }
            }
        case .wakeups:
            if let line = textField("Wakeups", in: body) {
                let nums = numbers(in: line)
                magnitude = nums.first; unit = "wakeups"
                detail = nums.count >= 2 ? "\(Int(nums[0])) wake-ups in \(Int(nums[1])) s" : line
            }
        case .diskWrites:
            // Confirmed layout (iOS 27.2.1): "Writes: 17.18 GB of file backed memory dirtied over 7274 seconds (…),
            // exceeding limit of 198.84 KB per second over 86400 seconds". The unit is read, never assumed.
            if let line = textField("Writes", in: body) {
                if let r = line.range(of: #"([\d.]+)\s*(KB|MB|GB|TB)"#, options: .regularExpression) {
                    let parts = line[r].split(separator: " ")
                    if let v = Double(parts[0]) {
                        let mult: Double = switch parts.last { case "KB": 1e3; case "MB": 1e6; case "TB": 1e12; default: 1e9 }
                        magnitude = v * mult / 1e9; unit = "GB"
                    }
                }
                let secs = textField("Writes duration", in: body).flatMap { numbers(in: $0).first }
                detail = magnitude.map { m in "wrote \(ByteFormatting.string(m * 1e9))" + (secs.map { " over \(DurationFormatting.string(seconds: $0))" } ?? "") + ", over its daily budget" } ?? line
            }
        default: break
        }
        let k: LogEvent.Kind = kind == .cpuResource ? .cpuResource : kind == .wakeups ? .wakeups : .diskWrites
        return [LogEvent(id: "\(importID)#0", kind: k, process: process, bundleID: header?.bundleID, timestamp: date,
                         magnitude: magnitude, magnitudeUnit: unit, detail: detail, importID: importID)]
    }

    /// JetsamEvent: one event for the jettisoned process(es) and one for the largest process.
    public static func parseJetsam(header: IPSHeader?, body: String, importID: String, fallbackDate: Date) -> [LogEvent] {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] else { return [] }
        let date = (json["date"] as? String).flatMap(IPSDate.parse) ?? header?.timestamp ?? fallbackDate
        let pageSize = ((json["memoryStatus"] as? [String: Any])?["pageSize"] as? NSNumber)?.doubleValue ?? 16_384
        let processes = json["processes"] as? [[String: Any]] ?? []
        var events: [LogEvent] = []
        for (i, p) in processes.enumerated() {
            guard let reason = p["reason"] as? String, let name = p["name"] as? String else { continue }
            let pages = (p["rpages"] as? NSNumber)?.doubleValue
            events.append(LogEvent(id: "\(importID)#j\(i)", kind: .jetsam, process: name, timestamp: date,
                                   magnitude: pages.map { $0 * pageSize / 1_048_576 }, magnitudeUnit: "MB", detail: reason, importID: importID))
        }
        if let largest = json["largestProcess"] as? String {
            let entry = processes.first { ($0["name"] as? String) == largest }
            let pages = (entry?["rpages"] as? NSNumber)?.doubleValue
            events.append(LogEvent(id: "\(importID)#largest", kind: .jetsamLargest, process: largest, timestamp: date,
                                   magnitude: pages.map { $0 * pageSize / 1_048_576 }, magnitudeUnit: "MB",
                                   detail: pages.map { "using \(Int($0 * pageSize / 1_048_576)) MB" }, importID: importID))
        }
        return events
    }

    public static func parsePanic(header: IPSHeader?, body: String, importID: String, fallbackDate: Date) -> [LogEvent] {
        let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
        let panicString = (json?["panicString"] as? String) ?? body
        let firstLine = panicString.split(separator: "\n").first.map(String.init)?.prefix(160)
        return [LogEvent(id: "\(importID)#0", kind: .panic, process: "kernel", timestamp: header?.timestamp ?? fallbackDate,
                         detail: firstLine.map(String.init), importID: importID)]
    }

    // MARK: Text helpers

    /// Value after "Key:" at the start of a line.
    static func textField(_ key: String, in body: String) -> String? {
        for line in body.split(separator: "\n", omittingEmptySubsequences: true).prefix(80) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(key + ":") {
                let v = t.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { return v }
            }
        }
        return nil
    }

    static func numbers(in s: String) -> [Double] {
        let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).flatMap { Double(s[$0]) } }
    }
}

import Foundation

// Daily analytics file (Settings > Privacy & Security > Analytics & Improvements > Analytics Data,
// "Analytics-YYYY-MM-DD-HHMMSS.ips.ca.synced", written about 08:00).
//
// CONFIRMED on a real iPhone Duo, iOS 27.2.1, 15 Nov 2026 (plan §4a): one JSON header line, then one JSON
// record per line: {"name": …, "message": {…}, "aggregationPeriod": "Daily", …}. Records are aggregated per
// day and carry NO timestamps, so anything taken from here is known only to the day.
// Records read (exact names):
//   OBCNoRotationBatteryHealthMetricsv2.last_value_CycleCount, OBC_Battery_Health_v3.sum_of_CycleCount
//   BatteryLevelReportView5 (currentBatteryCapacity samples, no times), UnpluggedDurationEnergyViewNew
//   PowerModesDailyEngagement (daily_total_Duration seconds per thermalPressureLevel)
//   PowerExceptionsDetectionEvents (ProcessName, LaunchdName, Count)
//   massStorage_power_coalitionInfo (process_name, sum_of_bytes_written / sum_of_bytes_read, in bytes)
//   deviceShutdownReasonDaily (ShutdownReason), ResetTelemetry2 (resetType, wdog, cpu_therm, …),
//   DeviceBootReason, RebootAndRollover (reason, Count)
//   InstallationResult (success, Count, error), ExpressSetup (dataSource), Datamigrator_* (isFromFactory,
//   previousBuildVersion), SpotlightIndexRebuild_Daily, HealthKit_CloudSync_Restore_DurationV3 (dbSize: UNIT NOT
//   STATED, finishedJournalMerge)
// Maximum capacity is NOT in this file as a readable number (confirmed). Vitals never derives it from here;
// only an explicit `…MaximumCapacityPercent` key would be used, and none was present on the Duo.

/// One day's summary from the analytics file.
public struct AnalyticsDay: Codable, Sendable, Hashable {
    public struct ProcessBytes: Codable, Sendable, Hashable {
        public var process: String
        public var bytesWritten: Double
        public var bytesRead: Double?
    }
    public struct ProcessFlag: Codable, Sendable, Hashable {
        public var process: String
        public var launchdName: String?
        public var count: Int
    }

    public var date: Date
    public var sourceFile: String
    public var osVersion: String?
    public var cycleCount: Int?
    /// Battery level samples (%), in file order. No times exist for them.
    public var batteryLevels: [Int]
    public var unpluggedSeconds: Double?
    public var unplugCount: Int?
    /// Seconds per thermal pressure level ("Nominal", "Light", "Moderate", "Heavy", "Trapping", "Sleeping").
    public var thermalPressureSeconds: [String: Double]
    public var powerExceptions: [ProcessFlag]
    /// Disk writes per process for the day, largest first, in bytes (the key names say bytes).
    public var diskWrites: [ProcessBytes]
    public var shutdownReasons: [String]
    public var resetTypes: [String]
    public var watchdogResets: Int
    public var thermalResets: Int
    public var reboots: Int
    public var successfulInstalls: Int
    public var failedInstalls: Int
    public var setupDataSource: String?
    public var fromFactory: Bool?
    public var previousBuild: String?
    public var spotlightRebuilds: Int
    public var healthRestoreUnfinished: Bool?
    /// HealthKit database size as written in the file; the unit is not stated.
    public var healthDBSizeNoUnit: Double?
    public var recordCount: Int

    /// Seconds at Light or above.
    public var elevatedThermalSeconds: Double {
        thermalPressureSeconds.filter { $0.key.lowercased() != "nominal" }.values.reduce(0, +)
    }

    /// Bytes written by processes in a glossary group (e.g. "icloudSync"), matched on the last name component.
    public func bytesWritten(group: String) -> Double {
        diskWrites.filter { ProcessGlossary.entry(for: $0.process)?.group == group }.map(\.bytesWritten).reduce(0, +)
    }

    public func bytesWritten(process: String) -> Double? {
        diskWrites.first { ProcessGlossary.shortName($0.process) == process }?.bytesWritten
    }

    public var looksLikeSetupDay: Bool {
        setupDataSource != nil || fromFactory == true || successfulInstalls >= 20
    }
}

public enum AnalyticsParser {
    public struct Result: Sendable {
        public var health: BatteryHealth?
        public var day: AnalyticsDay?
        public var events: [LogEvent]
        public var lineCount: Int
        public var coversDate: Date?
        public var notes: [String]
    }

    public static func parse(lines: some Sequence<Substring>, fileName: String, importID: String, fallbackDate: Date) -> Result {
        var header: IPSHeader?
        var count = 0, records = 0
        var day = AnalyticsDay(date: fallbackDate, sourceFile: fileName, osVersion: nil, cycleCount: nil, batteryLevels: [],
                               unpluggedSeconds: nil, unplugCount: nil, thermalPressureSeconds: [:], powerExceptions: [], diskWrites: [],
                               shutdownReasons: [], resetTypes: [], watchdogResets: 0, thermalResets: 0, reboots: 0, successfulInstalls: 0,
                               failedInstalls: 0, setupDataSource: nil, fromFactory: nil, previousBuild: nil, spotlightRebuilds: 0,
                               healthRestoreUnfinished: nil, healthDBSizeNoUnit: nil, recordCount: 0)
        var writes: [String: (Double, Double?)] = [:]
        var flags: [String: AnalyticsDay.ProcessFlag] = [:]
        var explicitPercent: (Double, String)?

        for (i, line) in lines.enumerated() {
            count += 1
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if i == 0, obj["bug_type"] != nil || obj["timestamp"] != nil {
                header = IPSParser.header(from: String(line))
                continue
            }
            guard let name = obj["name"] as? String else { continue }
            let m = obj["message"] as? [String: Any] ?? [:]
            records += 1
            func num(_ k: String) -> Double? { (m[k] as? NSNumber)?.doubleValue }
            func int(_ k: String) -> Int { Int(num(k) ?? 0) }
            let n = max(1, int("Count"))

            switch name {
            case "OBCNoRotationBatteryHealthMetricsv2":
                if let c = num("last_value_CycleCount") { day.cycleCount = Int(c) }
            case "OBC_Battery_Health_v3":
                if day.cycleCount == nil, let c = num("sum_of_CycleCount") { day.cycleCount = Int(c) }
            case "BatteryLevelReportView5":
                if let c = num("currentBatteryCapacity") { day.batteryLevels.append(Int(c)) }
            case "UnpluggedDurationEnergyViewNew":
                day.unpluggedSeconds = num("daily_total_Duration")
                day.unplugCount = num("daily_total_unplugged_count").map { Int($0) }
            case "PowerModesDailyEngagement":
                if let level = m["thermalPressureLevel"] as? String, let d = num("daily_total_Duration") {
                    day.thermalPressureSeconds[level, default: 0] += d
                }
            case "PowerExceptionsDetectionEvents":
                if let p = m["ProcessName"] as? String {
                    var f = flags[p] ?? AnalyticsDay.ProcessFlag(process: p, launchdName: m["LaunchdName"] as? String, count: 0)
                    f.count += n
                    flags[p] = f
                }
            case "massStorage_power_coalitionInfo":
                if let p = m["process_name"] as? String, let w = num("sum_of_bytes_written") {
                    let prev = writes[p] ?? (0, nil)
                    writes[p] = (prev.0 + w, num("sum_of_bytes_read").map { ($0) + (prev.1 ?? 0) } ?? prev.1)
                }
            case "deviceShutdownReasonDaily":
                if let r = (m["ShutdownReason"] as? String)?.trimmingCharacters(in: .whitespaces) { day.shutdownReasons.append(r) }
            case "ResetTelemetry2":
                if let t = m["resetType"] as? String { day.resetTypes.append(t) }
                if (m["wdog"] as? Bool) == true || (m["resetType"] as? String)?.contains("watchdog") == true { day.watchdogResets += 1 }
                if ["cpu_therm", "gpu_therm", "sochot", "ot"].contains(where: { (m[$0] as? Bool) == true }) { day.thermalResets += 1 }
            case "RebootAndRollover":
                if (m["reason"] as? String) == "reboot" { day.reboots += n }
            case "InstallationResult":
                if (m["success"] as? Bool) == true { day.successfulInstalls += n } else if m["success"] != nil { day.failedInstalls += n }
            case "ExpressSetup":
                day.setupDataSource = (m["dataSource"] as? String) ?? "unknown"
            case "SpotlightIndexRebuild_Daily":
                day.spotlightRebuilds += n
            case "HealthKit_CloudSync_Restore_DurationV3", "HealthKit_CloudSync_Restore_DurationV2", "HealthKit_CloudSync_Restore_Duration":
                if let f = m["finishedJournalMerge"] as? Bool { day.healthRestoreUnfinished = !f }
                if let s = num("dbSize") { day.healthDBSizeNoUnit = s }
            default:
                if name.hasPrefix("Datamigrator_") {
                    if let f = m["isFromFactory"] as? Bool { day.fromFactory = f }
                    if let b = m["previousBuildVersion"] as? String { day.previousBuild = b }
                }
                // An explicit percent key would be used if Apple ever adds one; none exists on iOS 27.2.1.
                if let v = num("last_value_MaximumCapacityPercent"), (30...110).contains(v) { explicitPercent = (v, "\(name).last_value_MaximumCapacityPercent") }
            }
        }
        // Watchdog resets also show in shutdown reasons when ResetTelemetry2 is absent.
        day.watchdogResets = max(day.watchdogResets, day.shutdownReasons.filter { $0.contains("wdog") }.count)
        day.diskWrites = writes.map { AnalyticsDay.ProcessBytes(process: $0.key, bytesWritten: $0.value.0, bytesRead: $0.value.1) }
            .sorted { $0.bytesWritten > $1.bytesWritten }
        day.powerExceptions = flags.values.sorted { $0.count > $1.count }
        day.recordCount = records
        day.osVersion = header?.osVersion
        let date = header?.timestamp ?? dateFromFileName(fileName) ?? fallbackDate
        day.date = date

        var notes: [String] = []
        var health: BatteryHealth?
        if day.cycleCount != nil || explicitPercent != nil {
            var keys: [String] = []
            if day.cycleCount != nil { keys.append("OBCNoRotationBatteryHealthMetricsv2.last_value_CycleCount") }
            if let e = explicitPercent { keys.append(e.1) }
            health = BatteryHealth(maxCapacityPercent: explicitPercent?.0, cycleCount: day.cycleCount, designCapacity: nil, fullChargeCapacity: nil,
                                   asOf: date, sourceFile: fileName, keysUsed: keys)
        }
        if explicitPercent == nil {
            notes.append("Maximum capacity is not in this file. Check Settings > Battery > Battery Health, or use the Mac companion.")
        }
        if records == 0 { notes.append("No daily records found. This may be a session file rather than the daily file; share the one written about 08:00.") }
        if header == nil { notes.append("No JSON header line; the date comes from the file name.") }

        // Day-precision events (no times exist in this file).
        var events: [LogEvent] = []
        let start = Calendar.current.startOfDay(for: date.addingTimeInterval(-6 * 3600))
        for w in day.diskWrites.prefix(12) where w.bytesWritten >= 1e9 {
            events.append(LogEvent(id: "\(importID)#dw-\(w.process)", kind: .diskWrites, process: ProcessGlossary.shortName(w.process), timestamp: start,
                                   magnitude: w.bytesWritten / 1e9, magnitudeUnit: "GB",
                                   detail: "wrote \(ByteFormatting.string(w.bytesWritten)) in the day (daily analytics, time not recorded)",
                                   importID: importID, precision: .day))
        }
        for f in day.powerExceptions {
            events.append(LogEvent(id: "\(importID)#pe-\(f.process)", kind: .powerException, process: ProcessGlossary.shortName(f.process), timestamp: start,
                                   magnitude: Double(f.count), magnitudeUnit: "flags", detail: "flagged \(f.count)× for power use (daily analytics)",
                                   importID: importID, precision: .day))
        }
        for (i, r) in day.shutdownReasons.enumerated() where r.contains("wdog") || r.contains("panic") {
            events.append(LogEvent(id: "\(importID)#rst\(i)", kind: .unexpectedRestart, process: "system", timestamp: start,
                                   detail: r, importID: importID, precision: .day))
        }
        return Result(health: health, day: records > 0 ? day : nil, events: events, lineCount: count, coversDate: date, notes: notes)
    }

    /// "Analytics-2026-11-14-093012.ips.ca.synced" → 2026-11-14 09:30:12 local time.
    public static func dateFromFileName(_ name: String) -> Date? {
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}(-\d{6})?"#, options: .regularExpression) else { return nil }
        let s = String(name[r])
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = s.count > 10 ? "yyyy-MM-dd-HHmmss" : "yyyy-MM-dd"
        return f.date(from: s)
    }
}

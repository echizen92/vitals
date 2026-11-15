import Foundation
import SQLite3

/// The app's local database: samples, imports, log events and small JSON documents (latest check-up,
/// battery health, hardware-test results, benchmark). Plain SQLite in the app-group container, in WAL
/// mode so the app and the widget extension can both write samples. No third-party dependency.
public actor VitalsStore {
    public enum StoreError: Error, CustomStringConvertible {
        case open(String), prepare(String), step(String)
        public var description: String {
            switch self { case .open(let s), .prepare(let s), .step(let s): s }
        }
    }

    nonisolated(unsafe) private var db: OpaquePointer?
    public let url: URL

    public init(url: URL = SharedContainer.databaseURL) throws {
        self.url = url
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw StoreError.open(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        sqlite3_busy_timeout(handle, 2000)
        try Self.exec(handle, """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS samples (
                takenAt REAL NOT NULL, thermal INTEGER NOT NULL, battery REAL, charge TEXT NOT NULL,
                lowPower INTEGER NOT NULL, source TEXT NOT NULL, tempC REAL);
            CREATE INDEX IF NOT EXISTS samples_time ON samples(takenAt);
            CREATE TABLE IF NOT EXISTS imports (id TEXT PRIMARY KEY, json BLOB NOT NULL, importedAt REAL NOT NULL);
            CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, importID TEXT NOT NULL, kind TEXT NOT NULL,
                process TEXT NOT NULL, ts REAL NOT NULL, json BLOB NOT NULL);
            CREATE INDEX IF NOT EXISTS events_time ON events(ts);
            CREATE TABLE IF NOT EXISTS docs (key TEXT PRIMARY KEY, json BLOB NOT NULL, updatedAt REAL NOT NULL);
            """)
        // v2: samples without an iOS thermal state (Mac companion). Ignore the error if the column exists.
        try? Self.exec(handle, "ALTER TABLE samples ADD COLUMN thermalUnknown INTEGER NOT NULL DEFAULT 0")
    }

    deinit { sqlite3_close_v2(db) }

    // MARK: Samples

    public func insert(_ s: Sample) throws {
        try run("INSERT INTO samples (takenAt, thermal, battery, charge, lowPower, source, tempC, thermalUnknown) VALUES (?,?,?,?,?,?,?,?)", [
            .real(s.takenAt.timeIntervalSince1970), .int(s.thermal.rawValue), s.batteryLevel.map(SQLValue.real) ?? .null,
            .text(s.charge.rawValue), .int(s.lowPowerMode ? 1 : 0), .text(s.source.rawValue), s.temperatureC.map(SQLValue.real) ?? .null,
            .int(s.thermalUnknown ? 1 : 0),
        ])
    }

    public func insert(_ samples: [Sample]) throws {
        try exec("BEGIN")
        do { for s in samples { try insert(s) }; try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }

    /// Inserts unless a sample from the same source is newer than `minGap`; several widgets reloading
    /// together then add one sample, not four. Returns whether it inserted.
    @discardableResult
    public func insertIfStale(_ s: Sample, minGap: TimeInterval = 5 * 60) throws -> Bool {
        let recent = try query("SELECT MAX(takenAt) FROM samples WHERE source = ?", [.text(s.source.rawValue)]) { $0.optionalDouble(0) }.first ?? nil
        if let r = recent, s.takenAt.timeIntervalSince1970 - r < minGap { return false }
        try insert(s)
        return true
    }

    public func samples(from: Date, to: Date = .distantFuture) throws -> [Sample] {
        try query("SELECT takenAt, thermal, battery, charge, lowPower, source, tempC, thermalUnknown FROM samples WHERE takenAt >= ? AND takenAt <= ? ORDER BY takenAt",
                  [.real(from.timeIntervalSince1970), .real(min(to.timeIntervalSince1970, 1e12))]) { row in
            Sample(takenAt: Date(timeIntervalSince1970: row.double(0)),
                   thermal: ThermalLevel(rawValue: row.int(1)) ?? .nominal,
                   batteryLevel: row.optionalDouble(2),
                   charge: ChargeState(rawValue: row.string(3)) ?? .unknown,
                   lowPowerMode: row.int(4) == 1,
                   source: SampleSource(rawValue: row.string(5)) ?? .app,
                   temperatureC: row.optionalDouble(6),
                   thermalUnknown: row.int(7) == 1)
        }
    }

    public func latestSample() throws -> Sample? {
        try samples(from: .distantPast).last
    }

    public func sampleCount() throws -> Int {
        try query("SELECT COUNT(*) FROM samples", []) { $0.int(0) }.first ?? 0
    }

    /// Keeps the store small: samples older than `days` are dropped.
    public func pruneSamples(olderThan days: Double = 30, now: Date = .now) throws {
        try run("DELETE FROM samples WHERE takenAt < ?", [.real(now.addingTimeInterval(-days * 86_400).timeIntervalSince1970)])
    }

    public func deleteSamples(source: SampleSource) throws {
        try run("DELETE FROM samples WHERE source = ?", [.text(source.rawValue)])
    }

    public func deleteAllSamples() throws { try exec("DELETE FROM samples") }

    // MARK: Imports and events

    public func save(_ record: ImportRecord, events: [LogEvent]) throws {
        try exec("BEGIN")
        do {
            try run("INSERT OR REPLACE INTO imports VALUES (?,?,?)", [.text(record.id), .blob(try JSON.encode(record)), .real(record.importedAt.timeIntervalSince1970)])
            for e in events {
                try run("INSERT OR REPLACE INTO events VALUES (?,?,?,?,?,?)", [.text(e.id), .text(e.importID), .text(e.kind.rawValue),
                                                                              .text(e.process), .real(e.timestamp.timeIntervalSince1970), .blob(try JSON.encode(e))])
            }
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
    }

    public func imports() throws -> [ImportRecord] {
        try query("SELECT json FROM imports ORDER BY importedAt DESC", []) { try JSON.decode(ImportRecord.self, $0.data(0)) }
    }

    public func events(from: Date = .distantPast, to: Date = .distantFuture) throws -> [LogEvent] {
        try query("SELECT json FROM events WHERE ts >= ? AND ts <= ? ORDER BY ts", [.real(max(from.timeIntervalSince1970, -1e12)), .real(min(to.timeIntervalSince1970, 1e12))]) {
            try JSON.decode(LogEvent.self, $0.data(0))
        }
    }

    public func deleteImport(id: String) throws {
        try run("DELETE FROM events WHERE importID = ?", [.text(id)])
        try run("DELETE FROM imports WHERE id = ?", [.text(id)])
    }

    // MARK: Documents

    public func put<T: Encodable>(_ value: T, key: String, now: Date = .now) throws {
        try run("INSERT OR REPLACE INTO docs VALUES (?,?,?)", [.text(key), .blob(try JSON.encode(value)), .real(now.timeIntervalSince1970)])
    }

    public func get<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try query("SELECT json FROM docs WHERE key = ?", [.text(key)]) { try JSON.decode(T.self, $0.data(0)) }.first
    }

    public func removeDoc(key: String) throws { try run("DELETE FROM docs WHERE key = ?", [.text(key)]) }

    // MARK: SQLite plumbing

    enum SQLValue { case null, int(Int), real(Double), text(String), blob(Data) }

    struct Row {
        let stmt: OpaquePointer
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func optionalDouble(_ i: Int32) -> Double? { sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, i) }
        func string(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        func data(_ i: Int32) -> Data {
            let n = Int(sqlite3_column_bytes(stmt, i))
            guard n > 0, let p = sqlite3_column_blob(stmt, i) else { return Data() }
            return Data(bytes: p, count: n)
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw StoreError.step(msg)
        }
    }

    private func exec(_ sql: String) throws {
        guard let db else { throw StoreError.open("closed") }
        try Self.exec(db, sql)
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, Int64(v))
            case .real(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            case .blob(let v): _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), Self.transient) }
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ args: [SQLValue]) throws {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError.step(String(cString: sqlite3_errmsg(db))) }
    }

    private func query<T>(_ sql: String, _ args: [SQLValue], _ map: (Row) throws -> T) throws -> [T] {
        let stmt = try prepare(sql, args)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(try map(Row(stmt: stmt))) }
            else if rc == SQLITE_DONE { break }
            else { throw StoreError.step(String(cString: sqlite3_errmsg(db))) }
        }
        return out
    }
}

/// Shared JSON settings: ISO-8601 dates, sorted keys, so exports diff cleanly.
public enum JSON {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        // ISO 8601 with milliseconds: log timestamps carry fractions of a second and must round-trip.
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try c.encode(f.string(from: date))
        }
        e.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys]
        return e
    }
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Double.self) { return Date(timeIntervalSince1970: n) }
            let s = try c.decode(String.self)
            if let d = ISO8601.parse(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised date \(s)")
        }
        return d
    }()
    public static func encode<T: Encodable>(_ v: T, pretty: Bool = false) throws -> Data { try encoder(pretty: pretty).encode(v) }
    public static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { try decoder.decode(t, from: d) }
}

public enum ISO8601 {
    public static func parse(_ s: String) -> Date? {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        a.formatOptions = [.withInternetDateTime]
        return a.date(from: s)
    }
}

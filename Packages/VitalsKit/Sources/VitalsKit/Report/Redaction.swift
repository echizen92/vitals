import Foundation

/// What to strip before a report leaves the phone. Everything defaults to redacted.
public struct RedactionOptions: Codable, Sendable, Hashable {
    public var deviceName = true
    /// Serial numbers, UDIDs, incident ids and similar.
    public var identifiers = true
    /// App and process names from logs become "App 1", "App 2"… consistently across the report.
    public var appNames = true
    /// Wi-Fi and network names. Vitals on iOS does not read Wi-Fi names; companion captures and notes may contain them.
    public var networkNames = true

    public init(deviceName: Bool = true, identifiers: Bool = true, appNames: Bool = true, networkNames: Bool = true) {
        self.deviceName = deviceName; self.identifiers = identifiers; self.appNames = appNames; self.networkNames = networkNames
    }

    public static let none = RedactionOptions(deviceName: false, identifiers: false, appNames: false, networkNames: false)
}

public enum Redactor {
    /// Returns a copy with the chosen fields replaced, and `redactions` listing what was done.
    public static func redact(_ report: VitalsReport, _ o: RedactionOptions) -> VitalsReport {
        var r = report
        var done: [String] = []

        if o.deviceName, r.device.name != nil {
            r.device.name = nil
            r.readings = r.readings.map { var x = $0; if x.id == "software.deviceName" { x.value = .text("[redacted]") }; return x }
            done.append("deviceName")
        } else if o.deviceName {
            r.readings = r.readings.map { var x = $0; if x.id == "software.deviceName" { x.value = .text("[redacted]") }; return x }
            done.append("deviceName")
        }

        if o.identifiers {
            // UDID and serial everywhere, including any that slipped into text (plan §4b item 13).
            let ids = Array((r.device.identifiers ?? [:]).values)
            func strip(_ s: String) -> String { ids.reduce(s) { $0.replacingOccurrences(of: $1, with: "[redacted]") } }
            if !ids.isEmpty {
                r.readings = r.readings.map { var x = $0; if case .text(let t) = x.value { x.value = .text(strip(t)) }; x.source = strip(x.source); return x }
                r.imports = r.imports.map { var i = $0; i.fileName = strip(i.fileName); i.notes = i.notes.map(strip); return i }
            }
            if r.device.identifiers != nil { r.device.identifiers = nil }
            r.device.osBuild = r.device.osBuild // build numbers are not identifying
            done.append("identifiers")
        }

        if o.appNames {
            var map: [String: String] = [:]
            func alias(_ name: String) -> String {
                if name == "kernel" { return name }
                if let a = map[name] { return a }
                let a = "App \(map.count + 1)"
                map[name] = a
                return a
            }
            // Stable order: by first appearance in time.
            let events = (r.events ?? []).sorted { $0.timestamp < $1.timestamp }
            for e in events { _ = alias(e.process) }
            for p in r.processSamples ?? [] { _ = alias(p.process) }
            func scrub(_ s: String) -> String {
                var out = s
                // Longest names first so "Photos Editor" is replaced before "Photos".
                for (name, a) in map.sorted(by: { $0.key.count > $1.key.count }) where name.count > 2 {
                    out = out.replacingOccurrences(of: name, with: a)
                }
                return out
            }
            r.events = r.events?.map { var e = $0; e.process = alias(e.process); e.bundleID = nil; e.detail = e.detail.map(scrub); return e }
            r.processSamples = r.processSamples?.map { var p = $0; p.process = alias(p.process); return p }
            r.findings = r.findings.map { f in
                var f = f
                f.summary = scrub(f.summary)
                f.detail = f.detail.map(scrub)
                f.evidence = f.evidence.map { var e = $0; e.text = scrub(e.text); e.source = e.source.map(scrub); return e }
                return f
            }
            r.imports = r.imports.map { var i = $0; i.fileName = scrub(i.fileName); i.notes = i.notes.map(scrub); return i }
            r.readings = r.readings.map { var x = $0; if case .text(let t) = x.value { x.value = .text(scrub(t)) }; x.source = scrub(x.source); return x }
            r.repairNotes = r.repairNotes.map(scrub)
            if var c = r.caseRecord {
                c.current.hypotheses = c.current.hypotheses.map { h in
                    var h = h; h.reasoning = h.reasoning.map { var e = $0; e.text = scrub(e.text); e.source = e.source.map(scrub); return e }; return h
                }
                r.caseRecord = c
            }
            done.append("appNames(\(map.count))")
        }

        if o.networkNames {
            r.readings = r.readings.filter { !$0.id.hasPrefix("network.ssid") }
            if var ids = r.device.identifiers {
                ids = ids.filter { !$0.key.lowercased().contains("ssid") && !$0.key.lowercased().contains("wifi") }
                r.device.identifiers = ids.isEmpty ? nil : ids
            }
            done.append("networkNames")
        }

        r.redactions = done
        return r
    }
}

import Foundation
import Testing
import CoreGraphics
@testable import VitalsKit

@Suite struct ReportTests {
    func sampleInput() async throws -> ReportBuilder.Input {
        let events = try ["Photos-2027-01-15-075510.ips", "mediaanalysisd.cpu_resource-2027-01-15-074530.ips", "JetsamEvent-2027-01-15-074002.ips"]
            .flatMap { try importFixture($0).events }
        let imports = try ["Photos-2027-01-15-075510.ips"].map { try importFixture($0).record }
        var s = FixedSystemSource.healthy
        s.thermalLevel = .serious
        let checkup = await CheckupRunner(source: s).runOnce(now: t0) {
            DiagnosisInput(readings: [], samples: SyntheticSamples.day(endingAt: t0).map { var x = $0; x.source = .app; return x }, logEvents: events)
        }
        let samples = SyntheticSamples.day(endingAt: t0).map { var x = $0; x.source = .app; return x }
        return ReportBuilder.Input(checkup: checkup, samples: samples, events: events, imports: imports,
                                   hardwareTests: [HardwareTestResult(kind: .touch, outcome: .passed, details: ["48 of 48 cells"], testedAt: t0)],
                                   benchmark: nil, repairNotes: "Screen replaced by Photos repair shop, 2026.", now: t0, appVersion: "1.0")
    }

    @Test func schemaRoundTrip() async throws {
        let report = ReportBuilder.build(try await sampleInput(), redaction: .none)
        let data = try ReportBuilder.json(report)
        let back = try JSON.decode(VitalsReport.self, data)
        #expect(back == report)
        #expect(back.schemaVersion == 1)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["schemaVersion", "generatedAt", "device", "readings", "samples", "hotSpells", "findings", "hardwareTests", "imports", "redactions"] {
            #expect(obj[key] != nil, "plan §7 field \(key) missing")
        }
        let reading = (obj["readings"] as! [[String: Any]]).first!
        for key in ["id", "area", "value", "unit", "provenance", "source", "takenAt"] where key != "unit" {
            #expect(reading[key] != nil, "reading field \(key) missing")
        }
    }

    @Test func toleratesMinimalCompanionStyleJSON() throws {
        let json = #"{"schemaVersion":1,"generatedAt":"2027-01-15T08:00:00Z","device":{"model":"iPhone Duo","modelIdentifier":"iPhone19,4","osVersion":"iOS 27.1"},"samples":[{"takenAt":"2027-01-15T07:00:00Z","thermal":2,"charge":"unplugged","lowPowerMode":false,"source":"companion","temperatureC":41.5}]}"#
        let r = try JSON.decode(VitalsReport.self, Data(json.utf8))
        #expect(r.samples.first?.temperatureC == 41.5)
        #expect(r.findings.isEmpty)
    }

    @Test func redactionDefaultsStripNamesConsistently() async throws {
        let report = ReportBuilder.build(try await sampleInput(), redaction: RedactionOptions())
        #expect(report.device.name == nil)
        #expect(report.readings.first { $0.id == "software.deviceName" }?.value == .text("[redacted]"))
        let names = Set(report.events?.map(\.process) ?? [])
        #expect(!names.contains("Photos"))
        #expect(!names.contains("mediaanalysisd"))
        #expect(names.allSatisfy { $0.hasPrefix("App ") || $0 == "kernel" })
        // Findings and notes use the same aliases.
        let all = report.findings.map(\.summary).joined() + report.findings.flatMap(\.evidence).map { $0.text + ($0.source ?? "") }.joined()
            + (report.repairNotes ?? "") + report.imports.map(\.fileName).joined()
        #expect(!all.contains("mediaanalysisd"))
        #expect(!all.contains("Photos"))
        #expect(report.redactions.contains("deviceName"))
        #expect(report.redactions.contains { $0.hasPrefix("appNames(") })
        #expect(report.events?.allSatisfy { $0.bundleID == nil } == true)
    }

    @Test func noRedactionKeepsNames() async throws {
        let report = ReportBuilder.build(try await sampleInput(), redaction: .none)
        #expect(report.events?.contains { $0.process == "Photos" } == true)
        #expect(report.redactions.isEmpty)
    }

    @Test func fixtureSamplesNeverEnterReport() async throws {
        var input = try await sampleInput()
        input.samples = SyntheticSamples.day(endingAt: t0)   // all .fixture
        #expect(ReportBuilder.build(input, redaction: .none).samples.isEmpty)
    }

    @Test func pdfRenders() async throws {
        let report = ReportBuilder.build(try await sampleInput(), redaction: RedactionOptions())
        let data = PDFRenderer.render(report)
        #expect(data.count > 5_000)
        #expect(data.starts(with: Array("%PDF".utf8)))
        let doc = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        #expect(doc.numberOfPages >= 2)
        // Write it out so it can be looked at by eye.
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("vitals-test-report.pdf"))
    }
}

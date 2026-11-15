import Foundation
import CoreGraphics
import CoreText

/// Renders a `VitalsReport` as an A4 PDF: cover summary, scorecard, findings with evidence, heat timeline,
/// hardware results, readings with provenance, imports and redactions. Pure CoreGraphics + CoreText, so it
/// works the same in the app, in tests on the Mac and (in spirit) matches the companion's output.
public enum PDFRenderer {
    static let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 in points
    static let margin: CGFloat = 48

    // Print palette (always light: paper is white).
    static let ink = CGColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
    static let ink2 = CGColor(srgbRed: 0.34, green: 0.36, blue: 0.38, alpha: 1)
    static let hairline = CGColor(srgbRed: 0.87, green: 0.86, blue: 0.83, alpha: 1)
    static func status(_ s: Status) -> CGColor {
        switch s {
        case .good, .expected: CGColor(srgbRed: 0.04, green: 0.45, blue: 0.39, alpha: 1)
        case .attention: CGColor(srgbRed: 0.56, green: 0.35, blue: 0, alpha: 1)
        case .problem: CGColor(srgbRed: 0.72, green: 0.2, blue: 0.16, alpha: 1)
        case .unknown: CGColor(srgbRed: 0.39, green: 0.42, blue: 0.43, alpha: 1)
        }
    }
    static func heat(_ t: ThermalLevel) -> CGColor {
        switch t {
        case .nominal: CGColor(srgbRed: 0.25, green: 0.84, blue: 0.72, alpha: 1)
        case .fair: CGColor(srgbRed: 1.0, green: 0.70, blue: 0.28, alpha: 1)
        case .serious: CGColor(srgbRed: 1.0, green: 0.56, blue: 0.32, alpha: 1)
        case .critical: CGColor(srgbRed: 1.0, green: 0.42, blue: 0.37, alpha: 1)
        }
    }

    /// Section ids, in order, so the app's "assembles itself" animation can mirror the PDF.
    public static let sections = ["Summary", "Scorecard", "Diagnosis", "Findings and advice", "Heat", "Hardware tests", "Readings", "Could not determine", "Files and redactions"]

    public static func render(_ r: VitalsReport) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = page
        let meta: [CFString: Any] = [kCGPDFContextTitle: "Vitals report", kCGPDFContextCreator: r.generator]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, meta as CFDictionary) else { return Data() }
        var w = Writer(ctx: ctx)
        w.newPage()

        // Cover summary.
        w.text("Vitals report", size: 28, weight: .bold)
        w.text("\(r.device.model) · \(r.device.osVersion)", size: 14, color: ink2)
        w.text("Generated \(r.generatedAt.formatted(date: .long, time: .shortened)) by \(r.generator)", size: 10, color: ink2)
        w.gap(14)
        let statuses = r.statuses ?? []
        let problems = statuses.filter { $0.status == .problem }.count, attention = statuses.filter { $0.status == .attention }.count
        let verdict = statuses.isEmpty ? "No check-up in this report." : problems > 0 ? "\(problems) problem\(problems == 1 ? "" : "s") found" : attention > 0 ? "\(attention) thing\(attention == 1 ? "" : "s") to look at" : "All clear"
        w.text(verdict, size: 20, weight: .semibold)
        w.text("Every value in this report is labelled: measured (read from iOS on the phone), from a log (read from a system file the owner shared), or inferred (worked out from other values). Values marked unverified come from undocumented file formats.", size: 10, color: ink2)
        w.gap(6)
        w.text("For Apple: this report is a cover sheet. Apple works from a sysdiagnose sent through Feedback Assistant or a support case.", size: 10, color: ink2)

        // Scorecard.
        w.heading("Scorecard")
        for s in statuses {
            w.statusRow(s.status, title: s.area.title, detail: s.sentence)
        }

        // Diagnosis case.
        if let c = r.caseRecord {
            w.heading("Diagnosis (\(c.current.state.label.lowercased()))")
            for h in c.current.hypotheses {
                w.statusRow(h.status, title: "\(h.title) · \(h.confidence.label) · \(h.tier.label)", detail: h.summary)
                for e in h.reasoning.prefix(8) { w.text("   \(e.text)  [\(e.provenance.label.lowercased())]", size: 8.5, color: ink2, mono: true) }
                w.gap(4)
            }
            if !c.history.isEmpty {
                w.text("Earlier verdicts", size: 11, weight: .semibold)
                for h in c.history { w.text("• \(h.at.formatted(date: .abbreviated, time: .shortened)): \(h.title) (\(h.confidence.label.lowercased()), \(h.state.label.lowercased()))", size: 9) }
            }
            if let facts = r.userFacts, !facts.isEmpty {
                for f in facts { w.text("You told Vitals: \(f.key.question) \(Int(f.value)) \(f.key.unit)", size: 9, color: ink2) }
            }
        }

        // Findings.
        w.heading("Findings and advice")
        if r.findings.isEmpty { w.text("No findings.", size: 11, color: ink2) }
        for f in r.findings.sorted(by: { $0.severity > $1.severity }) {
            let st: Status = f.severity == .problem ? .problem : f.severity == .attention ? .attention : .unknown
            w.statusRow(st, title: f.summary, detail: f.detail)
            for e in f.evidence.prefix(6) {
                w.text("   \(e.text)  [\(e.provenance.label.lowercased())\(e.source.map { ", \($0)" } ?? "")]", size: 8.5, color: ink2, mono: true)
            }
            let acts = AdviceCatalog.actions(for: f)
            if !acts.isEmpty { w.text("   What to do: " + acts.map(\.title).joined(separator: "; "), size: 9.5) }
            w.gap(4)
        }
        if let acts = r.actions, !acts.isEmpty {
            w.text("Actions taken", size: 11, weight: .semibold)
            for a in acts { w.text("• \(a.doneAt.formatted(date: .abbreviated, time: .shortened)) \(a.title): \(a.verdict.label)\(a.outcomeText.map { ". \($0)" } ?? "")", size: 9.5) }
        }

        // Heat.
        w.heading("Heat timeline (7 days)")
        if r.samples.isEmpty {
            w.text("No samples.", size: 11, color: ink2)
        } else {
            w.heatStrip(r.samples, from: r.generatedAt.addingTimeInterval(-7 * 86_400), to: r.generatedAt)
            w.text("\(r.samples.count) samples. Gaps are times Vitals had no chance to look (iOS allows sampling only while the app runs, in background refresh and on widget reloads).", size: 9, color: ink2)
        }
        for s in r.hotSpells.suffix(12) {
            w.text("• \(s.peak.label) from \(s.start.formatted(date: .abbreviated, time: .shortened)), \(Int(max(s.duration, 60) / 60)) min, \(s.wasCharging ? "charging" : "on battery")\(s.drainPerHour.map { ", draining \(Int($0.rounded()))%/h" } ?? "")", size: 10)
        }

        // Hardware.
        w.heading("Hardware tests")
        if r.hardwareTests.isEmpty { w.text("No hardware tests run.", size: 11, color: ink2) }
        for t in r.hardwareTests {
            let st: Status = t.outcome == .passed ? .good : t.outcome == .failed ? .problem : .unknown
            w.statusRow(st, title: "\(t.kind.title): \(t.outcome.label)", detail: ([t.notes] + t.details).filter { !$0.isEmpty }.joined(separator: " · "))
        }
        if let b = r.benchmark {
            w.gap(6)
            w.text("Benchmark \(b.takenAt.formatted(date: .abbreviated, time: .shortened)): \(b.summaryLine)\(b.hasBaseline ? "" : " (no baseline for this model)")", size: 10)
        }

        // Readings.
        w.heading("Readings")
        for area in Area.allCases {
            let rs = r.readings.filter { $0.area == area }
            if rs.isEmpty { continue }
            w.text(area.title, size: 11, weight: .semibold)
            for x in rs {
                w.text("\(x.label): \(x.displayValue)   [\(x.provenance.label.lowercased())\(x.unverified ? ", unverified" : ""), \(x.source)]", size: 8.5, mono: true)
            }
            w.gap(4)
        }

        if let cnd = r.couldNotDetermine, !cnd.isEmpty {
            w.heading("Could not determine")
            for c in cnd { w.text("• \(c)", size: 10) }
        }

        // Device details, notes, files, redactions.
        w.heading("Device, files and redactions")
        w.text("Model: \(r.device.model) (\(r.device.modelIdentifier))", size: 10)
        w.text("System: \(r.device.osVersion)\(r.device.osBuild.map { " (\($0))" } ?? "")", size: 10)
        if let n = r.device.name { w.text("Name: \(n)", size: 10) }
        if let ids = r.device.identifiers { for (k, v) in ids.sorted(by: { $0.key < $1.key }) { w.text("\(k): \(v)", size: 10) } }
        if let notes = r.repairNotes {
            w.gap(6)
            w.text("Repair and parts history (entered by the owner)", size: 11, weight: .semibold)
            w.text(notes, size: 10)
        }
        w.gap(6)
        w.text("Shared files", size: 11, weight: .semibold)
        if r.imports.isEmpty { w.text("None.", size: 10, color: ink2) }
        for i in r.imports { w.text("• \(i.kind.label): \(i.fileName) (\(i.eventCount) events)", size: 9) }
        w.gap(6)
        w.text("Redactions: \(r.redactions.isEmpty ? "none" : r.redactions.joined(separator: ", "))", size: 9, color: ink2)
        w.text("Report schema v\(r.schemaVersion). A machine-readable JSON twin of this report can be exported alongside.", size: 9, color: ink2)

        w.finish()
        ctx.closePDF()
        return data as Data
    }

    /// A simple top-down cursor that paginates.
    struct Writer {
        let ctx: CGContext
        var y: CGFloat = 0
        var pageNumber = 0
        let width = PDFRenderer.page.width - 2 * PDFRenderer.margin

        enum Weight { case regular, semibold, bold }

        mutating func newPage() {
            if pageNumber > 0 { footer(); ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            pageNumber += 1
            y = PDFRenderer.page.height - PDFRenderer.margin
        }

        mutating func finish() { footer(); ctx.endPDFPage() }

        func footer() {
            let s = attributed("Vitals · page \(pageNumber)", size: 8, color: PDFRenderer.ink2)
            draw(s, at: CGPoint(x: PDFRenderer.margin, y: 24), width: width)
        }

        mutating func ensure(_ h: CGFloat) { if y - h < PDFRenderer.margin { newPage() } }
        mutating func gap(_ h: CGFloat) { y -= h }

        func font(_ size: CGFloat, _ weight: Weight, mono: Bool) -> CTFont {
            if mono { return CTFontCreateWithName("Menlo" as CFString, size, nil) }
            let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            switch weight {
            case .regular: return base
            case .semibold, .bold:
                return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
            }
        }

        func attributed(_ s: String, size: CGFloat, weight: Weight = .regular, color: CGColor = PDFRenderer.ink, mono: Bool = false) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font(size, weight, mono: mono),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ])
        }

        func height(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
            let fs = CTFramesetterCreateWithAttributedString(a)
            return ceil(CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil).height)
        }

        func draw(_ a: NSAttributedString, at origin: CGPoint, width: CGFloat) {
            let h = height(a, width: width)
            let fs = CTFramesetterCreateWithAttributedString(a)
            let path = CGPath(rect: CGRect(x: origin.x, y: origin.y, width: width, height: h + 2), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(fs, CFRange(), path, nil), ctx)
        }

        mutating func text(_ s: String, size: CGFloat, weight: Weight = .regular, color: CGColor = PDFRenderer.ink, mono: Bool = false, indent: CGFloat = 0) {
            let a = attributed(s, size: size, weight: weight, color: color, mono: mono)
            let h = height(a, width: width - indent)
            if h > PDFRenderer.page.height - 2 * PDFRenderer.margin {
                // Very long text: split into lines and write them one by one.
                for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
                    text(String(line), size: size, weight: weight, color: color, mono: mono, indent: indent)
                }
                return
            }
            ensure(h)
            draw(a, at: CGPoint(x: PDFRenderer.margin + indent, y: y - h), width: width - indent)
            y -= h + 2
        }

        mutating func heading(_ s: String) {
            ensure(60)
            gap(14)
            ctx.setStrokeColor(PDFRenderer.hairline)
            ctx.setLineWidth(0.75)
            ctx.move(to: CGPoint(x: PDFRenderer.margin, y: y))
            ctx.addLine(to: CGPoint(x: PDFRenderer.margin + width, y: y))
            ctx.strokePath()
            gap(8)
            text(s, size: 15, weight: .bold)
            gap(4)
        }

        /// A status shape (circle, triangle, diamond, dashed ring) plus title and detail.
        mutating func statusRow(_ s: Status, title: String, detail: String?) {
            let t = attributed(title, size: 11, weight: .semibold)
            let d = detail.map { attributed($0, size: 9.5, color: PDFRenderer.ink2) }
            let h = height(t, width: width - 20) + (d.map { height($0, width: width - 20) } ?? 0) + 4
            ensure(h)
            let mark = CGRect(x: PDFRenderer.margin, y: y - 11, width: 9, height: 9)
            ctx.setFillColor(PDFRenderer.status(s))
            ctx.setStrokeColor(PDFRenderer.status(s))
            switch s {
            case .good: ctx.fillEllipse(in: mark)
            case .attention:
                ctx.move(to: CGPoint(x: mark.midX, y: mark.maxY)); ctx.addLine(to: CGPoint(x: mark.maxX, y: mark.minY)); ctx.addLine(to: CGPoint(x: mark.minX, y: mark.minY))
                ctx.closePath(); ctx.fillPath()
            case .problem:
                ctx.move(to: CGPoint(x: mark.midX, y: mark.maxY)); ctx.addLine(to: CGPoint(x: mark.maxX, y: mark.midY))
                ctx.addLine(to: CGPoint(x: mark.midX, y: mark.minY)); ctx.addLine(to: CGPoint(x: mark.minX, y: mark.midY)); ctx.closePath(); ctx.fillPath()
            case .unknown:
                ctx.setLineWidth(1); ctx.setLineDash(phase: 0, lengths: [1.5, 1.5]); ctx.strokeEllipse(in: mark); ctx.setLineDash(phase: 0, lengths: [])
            case .expected:
                ctx.setLineWidth(1.6); ctx.strokeEllipse(in: mark.insetBy(dx: 0.8, dy: 0.8))
            }
            let th = height(t, width: width - 20)
            draw(t, at: CGPoint(x: PDFRenderer.margin + 18, y: y - th), width: width - 20)
            y -= th
            if let d {
                let dh = height(d, width: width - 20)
                draw(d, at: CGPoint(x: PDFRenderer.margin + 18, y: y - dh), width: width - 20)
                y -= dh
            }
            y -= 6
        }

        mutating func heatStrip(_ samples: [Sample], from: Date, to: Date) {
            let h: CGFloat = 46
            ensure(h + 20)
            let x0 = PDFRenderer.margin
            let span = to.timeIntervalSince(from)
            let sorted = samples.filter(\.hasThermal).sorted { $0.takenAt < $1.takenAt }
            for (i, s) in sorted.enumerated() where s.takenAt >= from {
                let next = i + 1 < sorted.count ? min(sorted[i + 1].takenAt, s.takenAt.addingTimeInterval(45 * 60)) : s.takenAt.addingTimeInterval(10 * 60)
                let a = x0 + CGFloat(s.takenAt.timeIntervalSince(from) / span) * width
                let b = x0 + CGFloat(min(next, to).timeIntervalSince(from) / span) * width
                let bh = h * CGFloat(s.thermal.rawValue + 1) / 4
                ctx.setFillColor(PDFRenderer.heat(s.thermal))
                ctx.fill(CGRect(x: a, y: y - h, width: max(0.6, b - a), height: bh))
            }
            ctx.setStrokeColor(PDFRenderer.hairline)
            ctx.stroke(CGRect(x: x0, y: y - h, width: width, height: h))
            y -= h + 4
            text("\(from.formatted(date: .abbreviated, time: .omitted)) → \(to.formatted(date: .abbreviated, time: .omitted)). Bar height and colour: normal, warm, hot, very hot.", size: 8, color: PDFRenderer.ink2)
        }
    }
}

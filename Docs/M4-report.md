# M4 Report

## Built
- Schema v1 (`Report/Schema.swift`, documented in `Docs/report-schema.md`), with tolerant decoding so a minimal
  companion capture or an older file still reads.
- Redaction (`Report/Redaction.swift`), all on by default: device name, identifiers, app/process names from logs
  (stable aliases "App 1", "App 2" across events, findings, evidence text and sources, import names, readings and
  repair notes; bundle ids dropped; `kernel` kept), network names. The report lists what was redacted.
- `ReportBuilder`: check-up, a week of samples (fixture samples excluded), hot spells, findings, hardware tests,
  imports, events, benchmark, repair notes, scorecard statuses.
- PDF (`Report/PDFRenderer.swift`): A4, CoreGraphics + CoreText (runs on the Mac in tests). Cover summary with
  overall verdict and provenance legend, the "for Apple" cover-sheet note, scorecard with status shapes (not
  colour alone), findings with evidence and provenance, 7-day heat strip and hot spells, hardware tests and
  benchmark, readings with provenance and source, device details, repair history, shared files, redactions.
- Report screen: what the report is, the section list that fills in as the report is built, redaction toggles,
  repair-and-parts notes (saved), "include the original shared files" with the warning that originals are not
  redacted and the Feedback Assistant / Apple Support explanation, Export (share sheet with PDF + JSON + optional
  originals) and an in-app PDF preview (PDFKit). Prompts for a check-up if none has run.

## Verified, and how
- Tests (51 total): JSON round-trip with every plan §7 field present, decoding a minimal companion-style JSON,
  default redaction removes device name and every real process name from events, findings, evidence sources,
  import names and notes (a leak through evidence `source` was found by this test and fixed), no-redaction keeps
  names, fixture samples never reach a report, PDF renders (> 5 KB, `%PDF`, ≥ 2 pages).
- Rendered the test PDF to PNG and read it: layout, status shapes, evidence lines, heat strip.
- Duo simulator: Report screen, preview of a real export from the app's own data (`Docs/screens/m4-pdf-preview.png`):
  redaction aliases appear in file names, redaction list printed.

## Not verified
- Share sheet destinations (Mail, Files, AirDrop) were not exercised beyond presenting the sheet.
- Printing the PDF on paper.

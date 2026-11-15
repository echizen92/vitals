import SwiftUI
import PDFKit
import VitalsKit
import VitalsDesign

struct ReportScreen: View {
    @Environment(AppModel.self) private var model
    @State private var redaction = RedactionOptions()
    @State private var includeOriginals = false
    @State private var notes = ""
    @State private var built: BuiltReport?
    @State private var assembling = false
    @State private var assembled = 0
    @State private var showShare = false
    @State private var showPreview = false
    @Environment(\.motionLevel) private var motion

    struct BuiltReport { var pdf: URL; var json: URL; var originals: [URL]; var report: VitalsReport }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("A report you can hand to a repair shop, an engineer or Apple: a PDF to read and a JSON twin for tools.")
                            .font(.subheadline).foregroundStyle(VColor.ink2)
                        AssemblyList(assembled: assembled, assembling: assembling)
                    }
                    .padding(.vertical, 4)
                }
                if model.checkup == nil {
                    Section {
                        Label("No check-up yet. The report is much more useful with one.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(VColor.ink)
                        Button("Run a check-up now") { Task { await model.runCheckup() } }
                    }
                }

                Section {
                    Toggle("Device name", isOn: $redaction.deviceName)
                    Toggle("Serial numbers and identifiers", isOn: $redaction.identifiers)
                    Toggle("App and process names from logs", isOn: $redaction.appNames)
                    Toggle("Network names", isOn: $redaction.networkNames)
                } header: { Text("Redact before sharing") } footer: {
                    Text("On by default. Redacted app names become App 1, App 2… the same way throughout the report.")
                }

                Section {
                    TextField("Screen replaced at an Apple Store in 2026, genuine part…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: notes) { _, v in model.saveRepairNotes(v) }
                } header: { Text("Repair and parts history") } footer: {
                    Text("iOS shows genuine-part and repair history only in Settings > General > About. Copy it here by hand if it matters.")
                }

                Section {
                    Toggle("Include the original shared files", isOn: $includeOriginals)
                        .disabled(model.imports.isEmpty)
                } header: { Text("For Apple") } footer: {
                    Text("Apple's engineers work from a sysdiagnose sent through Feedback Assistant or an Apple Support case; this report is a cover sheet for that. Original files are not redacted.")
                }

                Section {
                    Button {
                        Task { await build(thenShare: true) }
                    } label: {
                        Label(assembling ? "Assembling…" : "Export PDF and JSON", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .vitalsButton(.primary)
                    .disabled(assembling)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    Button("Preview the PDF") { Task { await build(thenShare: false); showPreview = true } }
                        .disabled(assembling)
                }
            }
            .scrollContentBackground(.hidden)
            .vitalsGround()
            .navigationTitle("Report")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.showReport = false } } }
            .onAppear { notes = model.repairNotes }
            .sheet(isPresented: $showShare) {
                if let b = built { ShareSheet(items: [b.pdf, b.json] + b.originals) }
            }
            .sheet(isPresented: $showPreview) {
                if let b = built {
                    NavigationStack {
                        PDFPreview(url: b.pdf).ignoresSafeArea(edges: .bottom)
                            .navigationTitle(b.pdf.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreview = false } } }
                    }
                }
            }
        }
    }

    /// Builds the report; the section list fills in as each part is ready ("the report assembles itself").
    func build(thenShare: Bool) async {
        assembling = true
        assembled = 0
        let report = model.buildReport(redaction: redaction)
        let stem = ReportBuilder.fileStem(report)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("report", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdfURL = dir.appendingPathComponent("\(stem).pdf"), jsonURL = dir.appendingPathComponent("\(stem).json")
        let render = Task.detached { PDFRenderer.render(report) }
        // Step the list in time with real work; with motion off it fills at once.
        for i in 1...PDFRenderer.sections.count {
            if motion == .full { try? await Task.sleep(for: .milliseconds(110)) }
            withAnimation(Motion.change(motion, Motion.snappy)) { assembled = i }
        }
        let pdf = await render.value
        try? pdf.write(to: pdfURL)
        try? ReportBuilder.json(report).write(to: jsonURL)
        let originals = includeOriginals ? model.imports.compactMap(ImportLibrary.url(for:)).filter { FileManager.default.fileExists(atPath: $0.path) } : []
        built = BuiltReport(pdf: pdfURL, json: jsonURL, originals: originals, report: report)
        assembling = false
        if thenShare { showShare = true }
    }
}

struct AssemblyList: View {
    var assembled: Int
    var assembling: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(PDFRenderer.sections.enumerated()), id: \.offset) { i, name in
                HStack(spacing: 10) {
                    Image(systemName: i < assembled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(i < assembled ? VColor.fine : VColor.ink2.opacity(0.5))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    Text(name).font(.subheadline).foregroundStyle(i < assembled || !assembling ? VColor.ink : VColor.ink2)
                }
                .offset(x: assembling && i >= assembled ? 6 : 0)
                .opacity(assembling && i >= assembled ? 0.5 : 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(assembling ? "Assembling report, \(assembled) of \(PDFRenderer.sections.count) sections" : "Report sections: " + PDFRenderer.sections.joined(separator: ", "))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct PDFPreview: UIViewRepresentable {
    var url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) { v.document = PDFDocument(url: url) }
}

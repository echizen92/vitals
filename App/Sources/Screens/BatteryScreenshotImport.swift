import SwiftUI
import PhotosUI
import Vision
import VitalsKit
import VitalsDesign

/// Import a screenshot of Settings > Battery (per-app share) or Battery Health (maximum capacity), read with
/// on-device text recognition (Vision), then confirmed by the person (plan §4a item 3). The picker gives Vitals
/// only the one image chosen; no Photos permission is needed. The image is not kept.
struct BatteryScreenshotImport: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var result: BatteryScreenshotParser.Result?
    @State private var reading = false
    @State private var capacityText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Take a screenshot of Settings > Battery (tap the hours you care about first) or Settings > Battery > Battery Health. Vitals reads it on this phone and you check every value.")
                        .font(.subheadline).foregroundStyle(VColor.ink2)
                    PhotosPicker(selection: $item, matching: .screenshots) { Label("Choose the screenshot", systemImage: "photo") }
                    if reading { HStack { ProgressView(); Text("Reading on this phone…") } }
                }
                if let r = result {
                    if !r.apps.isEmpty {
                        Section {
                            ForEach(r.apps) { a in LabeledContent(a.app, value: "\(a.percent)%") }
                        } header: { Text("Battery use by app\(r.periodLabel.map { " · \($0)" } ?? "")") } footer: {
                            Text("If anything was misread, choose the screenshot again or skip it.")
                        }
                    }
                    Section {
                        TextField("Maximum capacity %", text: $capacityText).keyboardType(.numberPad)
                    } header: { Text("Maximum capacity") } footer: {
                        Text(r.maximumCapacity == nil ? "Not found in this screenshot. Type it from Battery Health, or leave it empty." : "Read as \(r.maximumCapacity!)%. Correct it if needed.")
                    }
                    if r.apps.isEmpty && r.maximumCapacity == nil {
                        Section { Text("Vitals could not read battery values from this image.").foregroundStyle(VColor.attention) }
                    }
                    Section {
                        Button("These are right, use them") { Task { await save(r); dismiss() } }.vitalsButton(.primary)
                    }
                }
            }
            .navigationTitle("Battery screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: item) { _, new in Task { await read(new) } }
        }
    }

    func read(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage else { return }
        reading = true
        defer { reading = false }
        let lines = await Task.detached { Self.recognise(image) }.value
        result = BatteryScreenshotParser.parse(lines)
        capacityText = result?.maximumCapacity.map(String.init) ?? ""
    }

    nonisolated static func recognise(_ image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let obs = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
        }
        // Join observations on the same row ("Safari" … "12%").
        var rows: [(y: CGFloat, text: String)] = []
        for o in obs {
            guard let t = o.topCandidates(1).first?.string else { continue }
            if let last = rows.last, abs(last.y - o.boundingBox.midY) < 0.012 { rows[rows.count - 1].text += " " + t }
            else { rows.append((o.boundingBox.midY, t)) }
        }
        return rows.map(\.text)
    }

    func save(_ r: BatteryScreenshotParser.Result) async {
        var saved = r
        if let v = Int(capacityText), (30...110).contains(v) {
            saved.maximumCapacity = v
            let h = BatteryHealth(maxCapacityPercent: Double(v), cycleCount: model.batteryHealth?.cycleCount ?? model.analyticsDays.compactMap(\.cycleCount).last,
                                  designCapacity: nil, fullChargeCapacity: nil, asOf: .now, sourceFile: "Settings screenshot", keysUsed: [],
                                  percentProvenance: .screenshot)
            model.batteryHealth = h
            try? await model.store?.put(h, key: DocKey.batteryHealth)
        }
        model.batteryShares = saved
        try? await model.store?.put(saved, key: DocKey.batteryShares)
        model.refreshDiagnosis()
    }
}

/// Per-app battery share from the confirmed screenshot.
struct BatterySharesCard: View {
    let result: BatteryScreenshotParser.Result
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(result.apps.prefix(8)) { a in
                HStack {
                    Text(a.app).font(.subheadline)
                    Spacer()
                    Text("\(a.percent)%").font(VFont.numeral(.subheadline))
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 6) {
                ProvenanceTag(.screenshot)
                if let p = result.periodLabel { Text(p).font(.caption2).foregroundStyle(VColor.ink2) }
            }
        }
    }
}

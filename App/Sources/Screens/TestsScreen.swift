import SwiftUI
import VitalsKit
import VitalsDesign

struct TestsScreen: View {
    @Environment(AppModel.self) private var model

    var suite: [HardwareTestKind] { HardwareTestKind.suite(isDuo: model.isDuo) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { DropCheckView() } label: {
                        HStack(spacing: Space.m) {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.title2).frame(width: 34).foregroundStyle(VColor.ink)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dropped your phone?").font(.headline).foregroundStyle(VColor.ink)
                                Text("One tap runs every check a drop can affect.").font(.subheadline).foregroundStyle(VColor.ink2)
                            }
                        }
                        .padding(.vertical, Space.xs)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    let done = suite.filter { k in model.hardwareResults.contains { $0.kind == k } }.count
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(done) of \(suite.count) tested").font(VFont.title).foregroundStyle(VColor.ink)
                        Text("Guided checks for repair technicians and anyone buying a used phone. Results go into the report.")
                            .font(.subheadline).foregroundStyle(VColor.ink2)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    ForEach(suite) { kind in
                        NavigationLink(value: kind) {
                            AdaptiveRow {
                                HStack(spacing: Space.m) {
                                    Image(systemName: kind.symbol).frame(width: 28).foregroundStyle(VColor.ink2).accessibilityHidden(true)
                                    Text(kind.title).foregroundStyle(VColor.ink)
                                }
                            } trailing: {
                                if let r = model.hardwareResults.first(where: { $0.kind == kind }) {
                                    HStack(spacing: 6) {
                                        StatusMark(r.outcome.status, size: 11)
                                        Text(r.outcome.label).font(.subheadline).foregroundStyle(VColor.status(r.outcome.status))
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } header: { SectionTitle("Hardware") }
                Section {
                    NavigationLink { BenchmarkView() } label: {
                        Label("Performance benchmark", systemImage: "speedometer")
                    }
                    NavigationLink { NetworkTestView() } label: {
                        Label("Network speed and latency", systemImage: "network")
                    }
                } header: { SectionTitle("Performance") } footer: {
                    Text("The network test is the only part of Vitals that uses the internet, and only when you start it.")
                }
            }
            .scrollContentBackground(.hidden)
            .vitalsGround()
            .navigationTitle("Tests")
            .navigationDestination(for: HardwareTestKind.self) { HardwareTestView(kind: $0) }
        }
    }
}

/// Routes each kind to its test.
struct HardwareTestView: View {
    let kind: HardwareTestKind
    var body: some View {
        switch kind {
        case .touch: TouchTest()
        case .display: DisplayTest()
        case .speakers: SpeakerTest()
        case .microphones: MicrophoneTest()
        case .cameras: CameraTest()
        case .haptics: HapticsTest()
        case .buttons: ButtonsTest()
        case .motion: MotionTest()
        case .proximity: ProximityTest()
        case .faceID: FaceIDTest()
        case .bluetooth: BluetoothTest()
        case .wifiCellular: PathTest()
        case .gps: GPSTest()
        case .nfc: NFCTest()
        case .flashlight: FlashlightTest()
        case .duoDisplays: DuoDisplaysTest()
        case .hinge: HingeTest()
        }
    }
}

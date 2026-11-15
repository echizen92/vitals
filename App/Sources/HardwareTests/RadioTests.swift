import SwiftUI
import CoreBluetooth
import CoreLocation
import CoreNFC
import Network
import VitalsKit
import VitalsDesign

// MARK: Bluetooth

@MainActor
@Observable
final class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    var state: CBManagerState = .unknown
    var seen = Set<UUID>()
    var scanning = false
    private var central: CBCentralManager?

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let newState = central.state
        MainActor.assumeIsolated {
            state = newState
            if newState == .poweredOn && !scanning {
                scanning = true
                self.central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                Task { try? await Task.sleep(for: .seconds(8)); self.stop() }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        MainActor.assumeIsolated { _ = seen.insert(id) }
    }

    func stop() { central?.stopScan(); scanning = false }
}

struct BluetoothTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var scanner = BluetoothScanner()

    var stateText: String {
        switch scanner.state {
        case .poweredOn: "On"
        case .poweredOff: "Off (turn on Bluetooth)"
        case .unauthorized: "Not allowed (Settings > Privacy & Security > Bluetooth)"
        case .unsupported: "Not supported here"
        case .resetting: "Resetting"
        default: "Starting…"
        }
    }

    var body: some View {
        TestPage(kind: .bluetooth, details: $details, suggested: $suggested) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Radio: \(stateText)").font(.headline)
                    Text(scanner.scanning ? "Scanning… \(scanner.seen.count) devices so far" : "\(scanner.seen.count) devices seen").font(.subheadline).foregroundStyle(VColor.ink2)
                    Text("Device names and addresses are not kept, only the count.").font(.caption).foregroundStyle(VColor.ink2)
                }
            }
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
        .onChange(of: scanner.scanning) { _, s in if !s { conclude() } }
        .onChange(of: scanner.state) { _, _ in conclude() }
    }

    func conclude() {
        details = ["Bluetooth: \(stateText)", "Devices seen in 8 s: \(scanner.seen.count)"]
        switch scanner.state {
        case .unsupported: suggested = .unavailable
        case .poweredOn where !scanner.scanning: suggested = scanner.seen.isEmpty ? .skipped : .passed
        default: break
        }
    }
}

// MARK: Wi-Fi and cellular

@MainActor
@Observable
final class PathWatcher {
    var wifi: NWPath.Status?
    var cellular: NWPath.Status?
    private var monitors: [NWPathMonitor] = []

    func start() {
        for type in [NWInterface.InterfaceType.wifi, .cellular] {
            let m = NWPathMonitor(requiredInterfaceType: type)
            m.pathUpdateHandler = { [weak self] p in
                let status = p.status
                Task { @MainActor in if type == .wifi { self?.wifi = status } else { self?.cellular = status } }
            }
            m.start(queue: DispatchQueue(label: "vitals.path.\(type)"))
            monitors.append(m)
        }
    }

    func stop() { monitors.forEach { $0.cancel() } }
}

struct PathTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var watcher = PathWatcher()

    func text(_ s: NWPath.Status?) -> String {
        switch s {
        case .satisfied: "Usable"
        case .unsatisfied: "Not usable"
        case .requiresConnection: "Needs connecting"
        default: "Checking…"
        }
    }

    var body: some View {
        TestPage(kind: .wifiCellular, details: $details, suggested: $suggested) {
            Panel {
                VStack(alignment: .leading, spacing: Space.m) {
                    row("Wi-Fi", watcher.wifi)
                    row("Cellular", watcher.cellular)
                }
            }
            Text("Shows whether each radio offers a working path right now. For speed and latency use the network test.").font(.caption).foregroundStyle(VColor.ink2)
        }
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
        .onChange(of: watcher.wifi) { _, _ in update() }
        .onChange(of: watcher.cellular) { _, _ in update() }
    }

    func row(_ t: String, _ s: NWPath.Status?) -> some View {
        HStack {
            StatusMark(s == .satisfied ? .good : s == nil ? .unknown : .attention, size: 11)
            Text(t).font(.headline)
            Spacer()
            Text(text(s)).foregroundStyle(VColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    func update() {
        details = ["Wi-Fi: \(text(watcher.wifi))", "Cellular: \(text(watcher.cellular))"]
        if watcher.wifi == .satisfied || watcher.cellular == .satisfied { suggested = .passed }
    }
}

// MARK: GPS

@MainActor
@Observable
final class LocationFix: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var accuracy: Double?
    var error: String?
    var started: Date?
    var timeToFix: Double?

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        started = .now
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let acc = locations.last?.horizontalAccuracy
        MainActor.assumeIsolated {
            accuracy = acc
            if let s = started { timeToFix = Date.now.timeIntervalSince(s) }
            // Only the accuracy is kept, never the position.
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let text = error.localizedDescription
        MainActor.assumeIsolated { self.error = text }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.requestLocation() }
        }
    }
}

struct GPSTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var fix = LocationFix()

    var body: some View {
        TestPage(kind: .gps, details: $details, suggested: $suggested) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    if let a = fix.accuracy {
                        BigValue("±\(Int(a.rounded()))", unit: "m", caption: "Horizontal accuracy\(fix.timeToFix.map { ", fix in \(Int($0)) s" } ?? "")")
                    } else if let e = fix.error {
                        Text(e).foregroundStyle(VColor.attention)
                    } else {
                        HStack { ProgressView(); Text("Getting a fix… go near a window or outside.") }
                    }
                    Text("Your location is not shown or stored, only its accuracy.").font(.caption).foregroundStyle(VColor.ink2)
                }
            }
        }
        .onAppear { fix.start() }
        .onChange(of: fix.accuracy) { _, a in
            guard let a else { return }
            details = ["Accuracy ±\(Int(a.rounded())) m", fix.timeToFix.map { "Time to fix \(Int($0)) s" } ?? ""].filter { !$0.isEmpty }
            suggested = a <= 100 ? .passed : .failed
        }
        .onChange(of: fix.error) { _, e in if let e { details = ["Error: \(e)"] } }
    }
}

// MARK: NFC

@MainActor
final class NFCProbe: NSObject, NFCTagReaderSessionDelegate {
    var onActive: (() -> Void)?
    var onEnd: ((String) -> Void)?
    private var session: NFCTagReaderSession?

    func start() {
        session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
        session?.alertMessage = "NFC is working if you see this. Hold a card near the top of the phone, or tap Cancel."
        session?.begin()
    }

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        MainActor.assumeIsolated { onActive?() }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let text = error.localizedDescription
        MainActor.assumeIsolated { onEnd?(text) }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        session.alertMessage = "A tag was detected."
        session.invalidate()
    }
}

struct NFCTest: View {
    @State private var details: [String] = []
    @State private var suggested: TestOutcome?
    @State private var probe = NFCProbe()

    var body: some View {
        TestPage(kind: .nfc, details: $details, suggested: $suggested) {
            if NFCTagReaderSession.readingAvailable {
                Button("Start NFC session") {
                    probe.onActive = { details = ["Reader session became active"]; suggested = .passed }
                    probe.onEnd = { msg in details.append("Session ended: \(msg)") }
                    probe.start()
                }
                .vitalsButton(.primary)
            } else {
                UnavailableNote(text: "NFC reading is not available on this device (the Simulator has none).")
            }
        }
        .onAppear { if !NFCTagReaderSession.readingAvailable { suggested = .unavailable; details = ["NFC reading: not available"] } }
    }
}

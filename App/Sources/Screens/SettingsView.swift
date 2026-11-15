import SwiftUI
import VitalsKit
import VitalsDesign

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var alertsOn = HeatAlerts.isEnabled
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Alert me when the phone runs hot", isOn: $alertsOn)
                        .onChange(of: alertsOn) { _, on in
                            Task { alertsOn = await HeatAlerts.setEnabled(on) }
                        }
                } header: { Text("Heat alerts") } footer: {
                    Text("iOS only lets Vitals look at the phone while it is open, during background refresh and when a widget updates. An alert can arrive late, or not at all if the phone cools before Vitals looks.")
                }

                Section {
                    LabeledContent("Samples stored", value: "\(model.samples.count) in 7 days")
                    LabeledContent("Shared with widgets", value: SharedContainer.isUsingGroup ? "Yes" : "No (app group unavailable)")
                    Button("Delete all samples and imports", role: .destructive) { confirmDelete = true }
                } header: { Text("Your data") } footer: {
                    Text("Everything stays on this phone. Vitals has no account, no analytics and no server. The only network use is the network test, when you start it.")
                }

                if showInjection {
                    Section {
                        Picker("State", selection: injectionBinding) {
                            Text("Live readings").tag(String?.none)
                            ForEach(InjectionPresets.allCases) { Text($0.label).tag(Optional($0.rawValue)) }
                        }
                        Button("Add a day of synthetic samples") { Task { await model.addSyntheticDay() } }
                        Button("Add synthetic logs for a hot spell") { Task { await model.addSyntheticLogs() } }
                        NavigationLink("Widget gallery") { WidgetGallery() }
                    } header: { Text("Simulator state") } footer: {
                        Text("The Simulator cannot produce real heat, battery or storage pressure. Injected values are labelled on every screen and are never real readings.")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    LabeledContent("Device", value: DeviceIdentity.modelName)
                    NavigationLink("Licences") { LicencesView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete all samples and imported files?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.deleteAllData() } }
            } message: { Text("This cannot be undone.") }
        }
    }

    var showInjection: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
        #endif
    }

    var injectionBinding: Binding<String?> {
        Binding(
            get: { InjectionPresets.allCases.first { $0.source.thermalLevel == model.injected?.thermalLevel && $0.source.storageRaw == model.injected?.storageRaw && $0.source.batteryRaw == model.injected?.batteryRaw && $0.source.networkRaw == model.injected?.networkRaw }?.rawValue },
            set: { model.injected = $0.flatMap(InjectionPresets.init(rawValue:))?.source; Task { await model.takeSample(source: .app) } }
        )
    }
}

struct LicencesView: View {
    var body: some View {
        ScrollView {
            Text("""
            Vitals for iPhone is released under the MIT licence. It uses no third-party code.

            The Mac companion (companion/ in the source) is GPL-3.0 because it builds on pymobiledevice3, which is GPL-3.0.
            """)
            .padding()
        }
        .navigationTitle("Licences")
    }
}

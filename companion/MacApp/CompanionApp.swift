import SwiftUI
import AppKit
import VitalsKit
import VitalsDesign

// Vitals Companion for Mac. GPL-3.0-or-later (companion/LICENSE): it drives pymobiledevice3.
// Follows PLAN.md section 6: a check-up, not a dashboard. One task at a time, verdict first.
// Packaging (plan 5.13): release builds bundle a pinned Python runtime with pymobiledevice3, so people install nothing.

@main
struct CompanionApp: App {
    @State private var runner = EngineRunner()

    var body: some Scene {
        Window("Vitals Companion", id: "main") {
            RootView()
                .environment(runner)
                .frame(minWidth: 900, minHeight: 620)
                .task { runner.check() }
        }
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("iPhone") {
                Button("Check Connection") { runner.check() }
                    .keyboardShortcut("r")
                    .disabled(runner.checking || runner.running)
                Divider()
                Button("Collect Logs") { runner.pullLogs() }
                    .keyboardShortcut("1")
                    .disabled(runner.running || runner.tier < 1)
                Button("Watch Live…") { runner.open(.live) }
                    .keyboardShortcut("2")
                    .disabled(runner.running || runner.tier < 1)
                Button("Test a Fix…") { runner.open(.fix) }
                    .keyboardShortcut("3")
                    .disabled(runner.running || runner.tier < 2)
                Divider()
                Button("Stop") { runner.stop() }
                    .keyboardShortcut(".")
                    .disabled(!runner.running)
                Button("Show in Finder") { runner.showInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(runner.lastOutput == nil)
                Button("All Tasks") { runner.goHome() }
                    .keyboardShortcut("0")
                    .disabled(runner.running || runner.task == .home)
            }
        }

        Settings {
            CompanionSettings().environment(runner)
        }
    }
}

struct RootView: View {
    @Environment(EngineRunner.self) private var runner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            ConnectionColumn()
                .navigationSplitViewColumnWidth(min: 280, ideal: 310, max: 360)
        } detail: {
            StageView()
        }
        .navigationTitle(runner.simulate ? "Vitals Companion — Simulated iPhone" : "Vitals Companion")
        // One switch for all animation: Reduce Motion turns every animated part to its still variant.
        // `-reduceMotion` forces the still variants for checking without changing the system setting.
        .environment(\.motionLevel, reduceMotion || ProcessInfo.processInfo.arguments.contains("-reduceMotion") ? .still : .full)
        .tint(VColor.ink)
    }
}

/// A proper Settings window: where results go, the connection, and the things only developers need.
struct CompanionSettings: View {
    @Environment(EngineRunner.self) private var runner

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { general }
            Tab("Advanced", systemImage: "wrench.and.screwdriver") { advanced }
        }
        .frame(width: 560)
        .scenePadding()
    }

    private var general: some View {
        @Bindable var runner = runner
        return Form {
            Section("Results") {
                LabeledContent("Save in") {
                    HStack {
                        Text(Plain.savedPath(runner.saveFolder)).truncationMode(.middle).lineLimit(1)
                        Button("Choose…") { chooseFolder() }
                        Button("Show") { NSWorkspace.shared.open(runner.saveFolder) }
                    }
                }
                Text("Logs and measurements are saved here, one folder each. Vitals never sends them anywhere; you choose when to AirDrop them.")
                    .font(.caption).foregroundStyle(.secondary)
                if !runner.saveFolderPath.isEmpty {
                    Button("Use Documents › Vitals") { runner.saveFolderPath = "" }
                }
            }
            Section("Connection") {
                Toggle("Reach iPhone over Wi-Fi", isOn: $runner.wifi)
                Text("For when the iPhone is not seen over USB. It must have trusted this Mac over USB once. It can briefly take the iPhone away from Xcode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        @Bindable var runner = runner
        return Form {
            Section("Testing") {
                Toggle("Simulated iPhone", isOn: $runner.simulate)
                Text("Uses made-up test data instead of a real iPhone. While it is on, the window title and the left column say so.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Measuring engine") {
                if runner.bundledPython == nil {
                    TextField("Python interpreter (development only)", text: $runner.pythonOverride)
                }
                LabeledContent("In use", value: runner.python)
                LabeledContent("Engine", value: runner.engineDir.path)
                Text("Release builds use the Python runtime and pymobiledevice3 bundled inside the app. In development, companion/engine/.venv is used when present.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Here"
        panel.directoryURL = runner.saveFolder
        if panel.runModal() == .OK, let url = panel.url { runner.saveFolderPath = url.path }
    }
}

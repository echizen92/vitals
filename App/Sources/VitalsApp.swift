import SwiftUI
import VitalsKit
import VitalsDesign

@main
struct VitalsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    model.scenePhaseChanged(phase)
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundSampler.register()
        UIDevice.current.isBatteryMonitoringEnabled = true
        MemoryWarningCounter.startCountingIfNeeded()
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        MemoryWarningCounter.record()
    }
}

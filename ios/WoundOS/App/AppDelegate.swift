import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize crash logger early so it captures everything
        CrashLogger.shared.log("App didFinishLaunching", category: .app)
        CrashLogger.shared.logDiagnostics("Launch Info", category: .app, data: [
            "launchOptions": launchOptions?.keys.map(\.rawValue) ?? [],
            "processId": ProcessInfo.processInfo.processIdentifier,
            "memoryFootprint": ProcessInfo.processInfo.physicalMemory,
        ])
        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        CrashLogger.shared.fault("MEMORY WARNING received", category: .app)
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

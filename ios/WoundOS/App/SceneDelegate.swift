import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        CrashLogger.shared.log("Scene willConnectTo — creating DependencyContainer", category: .app)
        guard let windowScene = scene as? UIWindowScene else {
            CrashLogger.shared.error("Failed to cast scene to UIWindowScene", category: .app)
            return
        }

        // Configure feature flags
        let container = DependencyContainer()
        FeatureFlags.configure(store: container.featureFlagStore)

        // UI test launch arguments
        if ProcessInfo.processInfo.arguments.contains("--enable-v5-lidar-capture") {
            FeatureFlags.setEnabled(.v5LidarCapture, true)
        }

        CrashLogger.shared.log("Feature flags configured, v5LidarCapture=\(FeatureFlags.isEnabled(.v5LidarCapture))", category: .app)

        let window = UIWindow(windowScene: windowScene)
        CrashLogger.shared.log("DependencyContainer created", category: .app)
        let navigationController = UINavigationController()

        appCoordinator = AppCoordinator(
            navigationController: navigationController,
            dependencies: container
        )
        appCoordinator?.start()

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
        CrashLogger.shared.log("Scene setup complete, window visible", category: .app)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        CrashLogger.shared.log("Scene did become active", category: .app)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        CrashLogger.shared.log("Scene will resign active", category: .app)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        CrashLogger.shared.log("Scene entered background", category: .app)
    }
}

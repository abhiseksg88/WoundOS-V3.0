import UIKit
import ARKit
import CaptureSync

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?
    private var container: DependencyContainer?

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

        let container = DependencyContainer()
        self.container = container
        FeatureFlags.configure(store: container.featureFlagStore)

        if ProcessInfo.processInfo.arguments.contains("--enable-v5-lidar-capture") {
            FeatureFlags.setEnabled(.v5LidarCapture, true)
        }

        CrashLogger.shared.log("Feature flags configured, v5LidarCapture=\(FeatureFlags.isEnabled(.v5LidarCapture))", category: .app)

        if FeatureFlags.isEnabled(.v5LidarCapture) {
            Self.printV5LaunchBanner()
        }

        let window = UIWindow(windowScene: windowScene)
        self.window = window

        if container.clinicalPlatformKeychain.loadToken() != nil,
           container.clinicalPlatformKeychain.loadVerifiedUser() != nil {
            CrashLogger.shared.log("Existing session found — launching main app", category: .app)
            showMainApp(container: container, in: window)
        } else {
            CrashLogger.shared.log("No session — showing login", category: .app)
            showLogin(container: container, in: window)
        }

        window.makeKeyAndVisible()
        observeLogout()
        CrashLogger.shared.log("Scene setup complete, window visible", category: .app)
    }

    // MARK: - Root Transitions

    func showMainApp(container: DependencyContainer, in window: UIWindow) {
        let navigationController = UINavigationController()
        appCoordinator = AppCoordinator(
            navigationController: navigationController,
            dependencies: container
        )
        appCoordinator?.start()
        window.rootViewController = navigationController
    }

    func showLogin(container: DependencyContainer, in window: UIWindow) {
        let loginVC = LoginViewController(
            keychain: container.clinicalPlatformKeychain,
            client: container.clinicalPlatformClient
        )
        loginVC.delegate = self
        window.rootViewController = loginVC
    }

    func logout() {
        guard let container, let window else { return }
        CrashLogger.shared.log("Logout — clearing session", category: .app)
        container.clinicalPlatformKeychain.deleteToken()
        container.clinicalPlatformKeychain.deleteVerifiedUser()
        appCoordinator = nil

        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
            self.showLogin(container: container, in: window)
        }
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

    // MARK: - Logout Notification

    private func observeLogout() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLogoutNotification),
            name: .carePlixLogout,
            object: nil
        )
    }

    @objc private func handleLogoutNotification() {
        logout()
    }

    private static func printV5LaunchBanner() {
        let device = UIDevice.current
        let lidarAvailable: Bool = {
            #if !targetEnvironment(simulator)
            return ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth])
            #else
            return false
            #endif
        }()
        #if DEBUG
        let buildConfig = "DEBUG"
        #else
        let buildConfig = "RELEASE"
        #endif
        print("""
        ================================================================
        WoundOS V5 — LiDAR Capture Mode ENABLED
        Device: \(device.model)
        iOS: \(device.systemVersion)
        LiDAR available: \(lidarAvailable ? "yes" : "no")
        Feature flags: v5_lidar_capture_enabled=ON
        Build: \(buildConfig)
        ================================================================
        """)
    }
}

// MARK: - LoginViewControllerDelegate

extension SceneDelegate: LoginViewControllerDelegate {
    func loginDidSucceed(user: VerifiedUser) {
        guard let container, let window else { return }
        CrashLogger.shared.log("Login succeeded — checking onboarding", category: .app)

        let onboardingKey = "onboarding_completed_\(user.userId)"
        if UserDefaults.standard.bool(forKey: onboardingKey) {
            UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
                self.showMainApp(container: container, in: window)
            }
        } else {
            let onboarding = OnboardingViewController(userName: user.name)
            onboarding.delegate = self
            UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
                window.rootViewController = onboarding
            }
        }
    }
}

// MARK: - OnboardingViewControllerDelegate

extension SceneDelegate: OnboardingViewControllerDelegate {
    func onboardingDidComplete() {
        guard let container, let window else { return }

        if let user = container.clinicalPlatformKeychain.loadVerifiedUser() {
            let onboardingKey = "onboarding_completed_\(user.userId)"
            UserDefaults.standard.set(true, forKey: onboardingKey)
        }

        CrashLogger.shared.log("Onboarding complete — launching main app", category: .app)
        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve) {
            self.showMainApp(container: container, in: window)
        }
    }
}

// MARK: - Logout Notification

extension Notification.Name {
    static let carePlixLogout = Notification.Name("com.careplix.logout")
}

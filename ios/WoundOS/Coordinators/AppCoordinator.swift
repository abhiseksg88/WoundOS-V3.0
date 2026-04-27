import UIKit
import WoundClinical

// MARK: - App Coordinator

/// Root coordinator. Manages the main tab bar and top-level navigation.
final class AppCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    init(navigationController: UINavigationController, dependencies: DependencyContainer) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func start() {
        let useClinicalLayout = FeatureFlags.isEnabled(.clinicalDashboard)
        CrashLogger.shared.log(
            "AppCoordinator.start() — \(useClinicalLayout ? "4-tab clinical" : "2-tab legacy") layout",
            category: .coordinator
        )

        let tabBarController = UITabBarController()

        if useClinicalLayout {
            tabBarController.viewControllers = buildClinicalTabs()
        } else {
            tabBarController.viewControllers = buildLegacyTabs()
        }

        tabBarController.selectedIndex = 0
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.setViewControllers([tabBarController], animated: false)
    }

    // MARK: - Legacy 2-Tab Layout

    private func buildLegacyTabs() -> [UIViewController] {
        let scanListNav = BrandedNavigationController()
        scanListNav.tabBarItem = UITabBarItem(
            title: "Scans",
            image: UIImage(systemName: "list.bullet.rectangle"),
            tag: 0
        )
        let scanListCoordinator = ScanListCoordinator(
            navigationController: scanListNav,
            dependencies: dependencies
        )
        addChild(scanListCoordinator)
        scanListCoordinator.start()

        let captureNav = BrandedNavigationController()
        captureNav.tabBarItem = UITabBarItem(
            title: "Capture",
            image: UIImage(systemName: "camera.viewfinder"),
            tag: 1
        )
        let captureCoordinator = CaptureCoordinator(
            navigationController: captureNav,
            dependencies: dependencies
        )
        addChild(captureCoordinator)
        captureCoordinator.start()

        return [scanListNav, captureNav]
    }

    // MARK: - Clinical 4-Tab Layout

    private func buildClinicalTabs() -> [UIViewController] {
        // Tab 1: Home Dashboard
        let homeNav = BrandedNavigationController()
        homeNav.tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage(systemName: "house.fill"),
            tag: 0
        )
        let dashboardCoordinator = DashboardCoordinator(
            navigationController: homeNav,
            dependencies: dependencies
        )
        addChild(dashboardCoordinator)
        dashboardCoordinator.start()

        // Tab 2: Patients
        let patientsNav = BrandedNavigationController()
        patientsNav.tabBarItem = UITabBarItem(
            title: "Patients",
            image: UIImage(systemName: "person.2.fill"),
            tag: 1
        )
        let patientCoordinator = PatientCoordinator(
            navigationController: patientsNav,
            dependencies: dependencies
        )
        addChild(patientCoordinator)
        patientCoordinator.start()

        // Tab 3: Capture
        let captureNav = BrandedNavigationController()
        captureNav.tabBarItem = UITabBarItem(
            title: "Capture",
            image: UIImage(systemName: "camera.viewfinder"),
            tag: 2
        )
        let captureCoordinator = CaptureCoordinator(
            navigationController: captureNav,
            dependencies: dependencies
        )
        addChild(captureCoordinator)
        captureCoordinator.start()

        // Tab 4: Settings
        let settingsNav = BrandedNavigationController()
        settingsNav.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape.fill"),
            tag: 3
        )
        let settingsCoordinator = SettingsCoordinator(
            navigationController: settingsNav,
            dependencies: dependencies
        )
        addChild(settingsCoordinator)
        settingsCoordinator.start()

        return [homeNav, patientsNav, captureNav, settingsNav]
    }
}

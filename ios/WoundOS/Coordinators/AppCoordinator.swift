import UIKit

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
        let tabBarController = UITabBarController()

        // Tab 1: Scan List (patient scan history)
        let scanListNav = UINavigationController()
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

        // Tab 2: New Capture
        let captureNav = UINavigationController()
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

        tabBarController.viewControllers = [scanListNav, captureNav]
        tabBarController.selectedIndex = 0

        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.setViewControllers([tabBarController], animated: false)
    }
}

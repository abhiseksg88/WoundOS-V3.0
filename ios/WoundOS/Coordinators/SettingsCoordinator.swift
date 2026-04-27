import UIKit

// MARK: - Settings Coordinator

/// Manages the settings tab and its sub-screens.
final class SettingsCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    init(navigationController: UINavigationController, dependencies: DependencyContainer) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func start() {
        let keychain = dependencies.clinicalPlatformKeychain
        let client = dependencies.clinicalPlatformClient
        let settingsVC = SettingsViewController(keychain: keychain)

        settingsVC.onClinicalPlatformTapped = { [weak self] in
            let clinicalVC = ClinicalPlatformSettingsViewController(
                keychain: keychain,
                client: client
            )
            self?.navigationController.pushViewController(clinicalVC, animated: true)
        }

        settingsVC.onDeveloperToolsTapped = { [weak self] in
            guard let self else { return }
            let debugVC = SegmenterDebugViewController(dependencies: self.dependencies)
            self.navigationController.pushViewController(debugVC, animated: true)
        }

        settingsVC.title = "Settings"
        navigationController.setViewControllers([settingsVC], animated: false)
    }
}

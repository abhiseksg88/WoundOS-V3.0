import UIKit
import WoundCore
import CaptureSync

// MARK: - Scan List Coordinator

/// Manages the scan history and detail views.
final class ScanListCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    init(navigationController: UINavigationController, dependencies: DependencyContainer) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func start() {
        let viewModel = ScanListViewModel(storage: dependencies.localStorage)
        viewModel.onScanSelected = { [weak self] scan in
            self?.showScanDetail(scan: scan)
        }

        let viewController = ScanListViewController(viewModel: viewModel, dependencies: dependencies)
        viewController.title = "Wound Scans"
        viewController.onSettingsTapped = { [weak self] in
            self?.showSettings()
        }
        navigationController.setViewControllers([viewController], animated: false)
    }

    private func showSettings() {
        let keychain = dependencies.clinicalPlatformKeychain
        let client = dependencies.clinicalPlatformClient

        let settingsVC = SettingsViewController(keychain: keychain)

        settingsVC.onClinicalPlatformTapped = { [weak settingsVC] in
            let clinicalVC = ClinicalPlatformSettingsViewController(
                keychain: keychain,
                client: client
            )
            settingsVC?.navigationController?.pushViewController(clinicalVC, animated: true)
        }

        settingsVC.onDeveloperToolsTapped = { [weak self, weak settingsVC] in
            guard let self else { return }
            let debugVC = SegmenterDebugViewController(dependencies: self.dependencies)
            settingsVC?.navigationController?.pushViewController(debugVC, animated: true)
        }

        let nav = UINavigationController(rootViewController: settingsVC)
        navigationController.present(nav, animated: true)
    }

    private func showScanDetail(scan: WoundScan) {
        let viewModel = ScanDetailViewModel(scan: scan)
        let viewController = ScanDetailViewController(viewModel: viewModel)
        viewController.title = "Scan Detail"
        navigationController.pushViewController(viewController, animated: true)
    }
}

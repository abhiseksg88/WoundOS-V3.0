import UIKit
import WoundCore

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

        let viewController = ScanListViewController(viewModel: viewModel)
        viewController.title = "Wound Scans"
        navigationController.setViewControllers([viewController], animated: false)
    }

    private func showScanDetail(scan: WoundScan) {
        let viewModel = ScanDetailViewModel(scan: scan)
        let viewController = ScanDetailViewController(viewModel: viewModel)
        viewController.title = "Scan Detail"
        navigationController.pushViewController(viewController, animated: true)
    }
}

import UIKit
import WoundClinical

// MARK: - Dashboard Coordinator

/// Manages the home dashboard and its drill-down flows.
final class DashboardCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    init(navigationController: UINavigationController, dependencies: DependencyContainer) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func start() {
        let viewModel = DashboardViewModel(
            clinicalStorage: dependencies.clinicalStorage,
            scanStorage: dependencies.localStorage
        )
        viewModel.onPatientSelected = { [weak self] patient in
            self?.showPatientDetail(patient: patient)
        }

        let viewController = DashboardViewController(viewModel: viewModel)
        viewController.title = "WoundOS"
        navigationController.setViewControllers([viewController], animated: false)
    }

    private func showPatientDetail(patient: Patient) {
        let viewModel = PatientDetailViewModel(
            patient: patient,
            storage: dependencies.clinicalStorage
        )
        let viewController = PatientDetailViewController(viewModel: viewModel)
        viewController.title = patient.fullName
        navigationController.pushViewController(viewController, animated: true)
    }
}

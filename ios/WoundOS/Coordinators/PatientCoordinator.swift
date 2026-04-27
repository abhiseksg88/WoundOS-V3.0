import UIKit
import WoundClinical

// MARK: - Patient Coordinator

/// Manages the patient list, detail, and form flows.
final class PatientCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    init(navigationController: UINavigationController, dependencies: DependencyContainer) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func start() {
        let viewModel = PatientListViewModel(storage: dependencies.clinicalStorage)
        viewModel.onPatientSelected = { [weak self] patient in
            self?.showPatientDetail(patient: patient)
        }
        viewModel.onAddPatientTapped = { [weak self] in
            self?.showPatientForm(patient: nil)
        }

        let viewController = PatientListViewController(viewModel: viewModel)
        viewController.title = "Patients"
        navigationController.setViewControllers([viewController], animated: false)
    }

    private func showPatientDetail(patient: Patient) {
        let viewModel = PatientDetailViewModel(
            patient: patient,
            storage: dependencies.clinicalStorage
        )
        viewModel.onEditPatient = { [weak self] patient in
            self?.showPatientForm(patient: patient)
        }
        viewModel.onWoundSelected = { [weak self] wound in
            self?.showWoundDetail(wound: wound)
        }
        viewModel.onStartAssessment = { [weak self] patient in
            self?.startCaptureFlow(patient: patient)
        }

        let viewController = PatientDetailViewController(viewModel: viewModel)
        viewController.title = patient.fullName
        navigationController.pushViewController(viewController, animated: true)
    }

    private func showPatientForm(patient: Patient?) {
        let viewModel = PatientFormViewModel(
            patient: patient,
            storage: dependencies.clinicalStorage
        )
        viewModel.onSave = { [weak self] in
            self?.navigationController.dismiss(animated: true)
            if let listVC = self?.navigationController.viewControllers.first as? PatientListViewController {
                listVC.refreshData()
            }
            if let detailVC = self?.navigationController.topViewController as? PatientDetailViewController {
                detailVC.refreshData()
            }
        }
        viewModel.onCancel = { [weak self] in
            self?.navigationController.dismiss(animated: true)
        }

        let formVC = PatientFormViewController(viewModel: viewModel)
        formVC.title = patient == nil ? "New Patient" : "Edit Patient"
        let nav = UINavigationController(rootViewController: formVC)
        navigationController.present(nav, animated: true)
    }

    private func showWoundDetail(wound: Wound) {
        // Phase 5D — will push wound-specific scan history
    }

    private func startCaptureFlow(patient: Patient) {
        // Phase 5D — will transition to enhanced capture coordinator
    }
}

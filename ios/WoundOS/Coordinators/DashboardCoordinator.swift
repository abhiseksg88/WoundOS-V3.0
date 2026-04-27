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
        viewModel.onEditPatient = { [weak self] patient in
            self?.showPatientForm(patient: patient)
        }
        viewModel.onWoundSelected = { _ in }
        viewModel.onStartAssessment = { [weak self] patient in
            self?.startCaptureFlow(patient: patient)
        }

        let viewController = PatientDetailViewController(viewModel: viewModel)
        viewController.title = patient.fullName
        navigationController.pushViewController(viewController, animated: true)
    }

    private func showPatientForm(patient: Patient) {
        let viewModel = PatientFormViewModel(
            patient: patient,
            storage: dependencies.clinicalStorage
        )
        viewModel.onSave = { [weak self] in
            self?.navigationController.dismiss(animated: true)
            if let detailVC = self?.navigationController.topViewController as? PatientDetailViewController {
                detailVC.refreshData()
            }
        }
        viewModel.onCancel = { [weak self] in
            self?.navigationController.dismiss(animated: true)
        }

        let formVC = PatientFormViewController(viewModel: viewModel)
        formVC.title = "Edit Patient"
        let nav = UINavigationController(rootViewController: formVC)
        navigationController.present(nav, animated: true)
    }

    private func startCaptureFlow(patient: Patient) {
        Task { @MainActor in
            let wounds = (try? await dependencies.clinicalStorage.fetchWounds(patientId: patient.id)) ?? []
            let wound: Wound
            if let first = wounds.first {
                wound = first
            } else {
                wound = Wound(
                    patientId: patient.id,
                    label: "W1",
                    woundType: .other,
                    anatomicalLocation: AnatomicalLocation(region: .other, laterality: .notApplicable)
                )
                try? await dependencies.clinicalStorage.saveWound(wound)
            }

            let captureNav = BrandedNavigationController()
            let captureCoordinator = CaptureCoordinator(
                navigationController: captureNav,
                dependencies: dependencies
            )
            captureCoordinator.clinicalContext = ClinicalCaptureContext(patient: patient, wound: wound)
            captureCoordinator.onFlowComplete = { [weak self, weak captureNav] in
                captureNav?.dismiss(animated: true)
                if let idx = self?.childCoordinators.firstIndex(where: { $0 === captureCoordinator }) {
                    self?.childCoordinators.remove(at: idx)
                }
                if let detailVC = self?.navigationController.topViewController as? PatientDetailViewController {
                    detailVC.refreshData()
                }
            }

            childCoordinators.append(captureCoordinator)
            captureCoordinator.start()
            captureNav.modalPresentationStyle = .fullScreen
            navigationController.present(captureNav, animated: true)
        }
    }
}

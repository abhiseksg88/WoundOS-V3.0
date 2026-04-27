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
        Task { @MainActor in
            let wounds = (try? await dependencies.clinicalStorage.fetchWounds(patientId: patient.id)) ?? []

            if wounds.isEmpty {
                showWoundCreationThenCapture(patient: patient)
            } else if wounds.count == 1 {
                launchCapture(patient: patient, wound: wounds[0])
            } else {
                showWoundPicker(patient: patient, wounds: wounds)
            }
        }
    }

    private func showWoundPicker(patient: Patient, wounds: [Wound]) {
        let alert = UIAlertController(title: "Select Wound", message: "Which wound are you assessing?", preferredStyle: .actionSheet)
        for wound in wounds {
            alert.addAction(UIAlertAction(title: "\(wound.label) — \(wound.woundType.displayName)", style: .default) { [weak self] _ in
                self?.launchCapture(patient: patient, wound: wound)
            })
        }
        alert.addAction(UIAlertAction(title: "New Wound", style: .default) { [weak self] _ in
            self?.showWoundCreationThenCapture(patient: patient)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        navigationController.present(alert, animated: true)
    }

    private func showWoundCreationThenCapture(patient: Patient) {
        let newWound = Wound(
            patientId: patient.id,
            label: "W1",
            woundType: .other,
            anatomicalLocation: AnatomicalLocation(region: .other, laterality: .notApplicable)
        )
        Task { @MainActor in
            try? await dependencies.clinicalStorage.saveWound(newWound)
            launchCapture(patient: patient, wound: newWound)
        }
    }

    private func launchCapture(patient: Patient, wound: Wound) {
        let captureNav = BrandedNavigationController()
        let captureCoordinator = CaptureCoordinator(
            navigationController: captureNav,
            dependencies: dependencies
        )
        captureCoordinator.clinicalContext = ClinicalCaptureContext(patient: patient, wound: wound)
        captureCoordinator.onFlowComplete = { [weak self, weak captureNav] in
            captureNav?.dismiss(animated: true)
            if let childIdx = self?.childCoordinators.firstIndex(where: { $0 === captureCoordinator }) {
                self?.childCoordinators.remove(at: childIdx)
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

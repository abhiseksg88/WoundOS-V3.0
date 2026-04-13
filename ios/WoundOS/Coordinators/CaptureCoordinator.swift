import UIKit
import WoundCore

// MARK: - Capture Coordinator

/// Manages the full capture → draw → measure → save flow.
/// This is the primary clinical workflow.
final class CaptureCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    init(navigationController: UINavigationController, dependencies: DependencyContainer) {
        self.navigationController = navigationController
        self.dependencies = dependencies
    }

    func start() {
        showCapture()
    }

    // MARK: - Step 1: AR Capture

    private func showCapture() {
        let viewModel = CaptureViewModel(captureProvider: dependencies.captureProvider)
        viewModel.onCaptureComplete = { [weak self] snapshot, qualityScore in
            self?.showBoundaryDrawing(snapshot: snapshot, qualityScore: qualityScore)
        }

        let viewController = CaptureViewController(viewModel: viewModel)
        viewController.title = "Capture Wound"
        navigationController.setViewControllers([viewController], animated: false)
    }

    // MARK: - Step 2: Boundary Drawing

    private func showBoundaryDrawing(snapshot: CaptureSnapshot, qualityScore: CaptureQualityScore?) {
        let viewModel = BoundaryDrawingViewModel(
            snapshot: snapshot,
            measurementEngine: dependencies.measurementEngine,
            qualityScoreSnapshot: qualityScore
        )
        viewModel.onMeasurementComplete = { [weak self] scan in
            self?.showMeasurementResult(scan: scan)
        }

        let viewController = BoundaryDrawingViewController(viewModel: viewModel)
        viewController.title = "Draw Wound Boundary"
        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - Step 3: Measurement Results + PUSH Input

    private func showMeasurementResult(scan: WoundScan) {
        let viewModel = MeasurementResultViewModel(
            scan: scan,
            storage: dependencies.localStorage,
            uploadManager: dependencies.uploadManager
        )
        viewModel.onSaveComplete = { [weak self] in
            self?.showCapture() // Return to capture for next wound
        }

        let viewController = MeasurementResultViewController(viewModel: viewModel)
        viewController.title = "Measurement Results"
        navigationController.pushViewController(viewController, animated: true)
    }
}

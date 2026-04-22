import UIKit
import SwiftUI
import WoundCore
import WoundCapture

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
        CrashLogger.shared.log("CaptureCoordinator.start()", category: .coordinator)
        showCapture()
    }

    // MARK: - Step 1: AR Capture

    private func showCapture() {
        // V5 path: enhanced LiDAR capture with guided SwiftUI views
        if FeatureFlags.isEnabled(.v5LidarCapture) {
            showV5Capture()
            return
        }

        // V4 path: unchanged
        CrashLogger.shared.log("Navigating to AR Capture screen (V4)", category: .coordinator)
        let viewModel = CaptureViewModel(captureProvider: dependencies.captureProvider)
        viewModel.onCaptureComplete = { [weak self] snapshot, qualityScore in
            CrashLogger.shared.log("Capture complete — transitioning to Boundary Drawing", category: .coordinator)
            CrashLogger.shared.logDiagnostics("Capture Snapshot", category: .capture, data: [
                "imageWidth": snapshot.imageWidth,
                "imageHeight": snapshot.imageHeight,
                "depthWidth": snapshot.depthWidth,
                "depthHeight": snapshot.depthHeight,
                "vertexCount": snapshot.vertices.count,
                "faceCount": snapshot.faces.count,
                "normalCount": snapshot.normals.count,
                "depthMapSize": snapshot.depthMap.count,
                "confidenceMapSize": snapshot.confidenceMap.count,
                "rgbDataSize": snapshot.rgbImageData.count,
                "device": snapshot.deviceModel,
            ])
            self?.showBoundaryDrawing(snapshot: snapshot, qualityScore: qualityScore)
        }

        let viewController = CaptureViewController(viewModel: viewModel)
        viewController.title = "Capture Wound"
        navigationController.setViewControllers([viewController], animated: false)
    }

    // MARK: - V5 Capture Path

    private func showV5Capture() {
        CrashLogger.shared.log("Navigating to V5 Capture screen", category: .coordinator)
        guard let captureSession = dependencies.v5CaptureSession else {
            CrashLogger.shared.error("V5 flag ON but v5CaptureSession is nil — falling back to V4", category: .coordinator)
            showCapture()
            return
        }

        let viewModel = V5CaptureViewModel(captureSession: captureSession)
        viewModel.onCaptureComplete = { [weak self] bundle in
            CrashLogger.shared.log("V5 Capture complete — transitioning to Boundary Drawing", category: .coordinator)
            CrashLogger.shared.logDiagnostics("V5 CaptureBundle", category: .capture, data: [
                "captureId": bundle.id.uuidString,
                "mode": bundle.captureMode.rawValue,
                "qualityTier": bundle.qualityScore.tier.rawValue,
                "confidence": bundle.confidenceSummary.overallScore,
                "vertexCount": bundle.captureData.vertexCount,
                "faceCount": bundle.captureData.faceCount,
            ])

            // Persist the bundle to SwiftData
            if let store = self?.dependencies.captureBundleStore {
                Task { @MainActor in
                    try? store.save(bundle)
                }
            }

            // Bridge CaptureBundle → CaptureSnapshot for existing V4 pipeline
            let snapshot = bundle.captureData.toCaptureSnapshot(timestamp: bundle.capturedAt)
            let qualityScore = bundle.qualityScore
            self?.showBoundaryDrawing(snapshot: snapshot, qualityScore: qualityScore)
        }

        let hostingVC = V5CaptureHostingController(viewModel: viewModel)
        hostingVC.title = "Capture Wound"
        navigationController.setViewControllers([hostingVC], animated: false)
    }

    // MARK: - Step 2: Boundary Drawing

    private func showBoundaryDrawing(snapshot: CaptureSnapshot, qualityScore: CaptureQualityScore?) {
        CrashLogger.shared.log("Navigating to Boundary Drawing screen", category: .coordinator)
        if let q = qualityScore {
            CrashLogger.shared.logDiagnostics("Pre-Capture Quality", category: .capture, data: [
                "trackingStableSeconds": q.trackingStableSeconds,
                "captureDistanceM": q.captureDistanceM,
                "meshVertexCount": q.meshVertexCount,
                "angularVelocity": q.angularVelocityRadPerSec,
            ])
        }
        let viewModel = BoundaryDrawingViewModel(
            snapshot: snapshot,
            measurementEngine: dependencies.measurementEngine,
            segmenter: dependencies.autoSegmenter,
            qualityScoreSnapshot: qualityScore
        )
        viewModel.onMeasurementComplete = { [weak self] scan in
            CrashLogger.shared.log("Measurement complete — transitioning to Results", category: .coordinator)
            self?.showMeasurementResult(scan: scan)
        }

        let viewController = BoundaryDrawingViewController(viewModel: viewModel)
        viewController.title = "Draw Wound Boundary"
        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - Step 3: Measurement Results + PUSH Input

    private func showMeasurementResult(scan: WoundScan) {
        CrashLogger.shared.log("Navigating to Measurement Results screen", category: .coordinator)
        CrashLogger.shared.logDiagnostics("Measurement Results", category: .measurement, data: [
            "areaCm2": scan.primaryMeasurement.areaCm2,
            "lengthMm": scan.primaryMeasurement.lengthMm,
            "widthMm": scan.primaryMeasurement.widthMm,
            "maxDepthMm": scan.primaryMeasurement.maxDepthMm,
            "meanDepthMm": scan.primaryMeasurement.meanDepthMm,
            "volumeMl": scan.primaryMeasurement.volumeMl,
            "perimeterMm": scan.primaryMeasurement.perimeterMm,
            "processingTimeMs": scan.primaryMeasurement.processingTimeMs,
            "pushScore": scan.pushScore.totalScore,
        ])
        let viewModel = MeasurementResultViewModel(
            scan: scan,
            storage: dependencies.localStorage,
            uploadManager: dependencies.uploadManager
        )
        viewModel.onSaveComplete = { [weak self] in
            CrashLogger.shared.log("Save complete — returning to Capture", category: .coordinator)
            self?.showCapture() // Return to capture for next wound
        }

        let viewController = MeasurementResultViewController(viewModel: viewModel)
        viewController.title = "Measurement Results"
        navigationController.pushViewController(viewController, animated: true)
    }
}

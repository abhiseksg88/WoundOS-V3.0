import UIKit
import SwiftUI
import WoundCore
import WoundCapture
import WoundClinical

// MARK: - Clinical Context

struct ClinicalCaptureContext {
    let patient: Patient
    let wound: Wound
}

// MARK: - Capture Coordinator

/// Manages the full capture → draw → measure → save flow.
/// This is the primary clinical workflow.
final class CaptureCoordinator: Coordinator {

    let navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    let dependencies: DependencyContainer

    /// When set, the capture was initiated from Patient Detail ("Start Assessment")
    /// and the post-measurement flow skips patient assignment.
    var clinicalContext: ClinicalCaptureContext?

    /// Called when the entire capture + assessment flow completes.
    var onFlowComplete: (() -> Void)?

    private var pendingManualMeasurements: ManualMeasurements?

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

        let useClinicalFlow = FeatureFlags.isEnabled(.clinicalAssessment)

        let viewModel = MeasurementResultViewModel(
            scan: scan,
            storage: dependencies.localStorage,
            uploadManager: dependencies.uploadManager,
            showContinueToAssessment: useClinicalFlow
        )

        viewModel.onSaveComplete = { [weak self] in
            CrashLogger.shared.log("Save complete — returning to Home", category: .coordinator)
            self?.finishFlow()
        }

        viewModel.onContinueToAssessment = { [weak self, weak viewModel] in
            guard let self else { return }
            CrashLogger.shared.log("Continue to assessment — clinical flow", category: .coordinator)

            var manualMeasurements: ManualMeasurements?
            if let vm = viewModel {
                let length = Double(vm.manualLengthCm)
                let width = Double(vm.manualWidthCm)
                let depth = Double(vm.manualDepthCm)
                if length != nil || width != nil || depth != nil {
                    let source: ManualMeasurementSource
                    switch vm.manualMethod {
                    case .ruler: source = .nurseEntered
                    case .tracing: source = .nurseEntered
                    case .digital: source = .nurseEntered
                    }
                    manualMeasurements = ManualMeasurements(
                        lengthCm: length,
                        widthCm: width,
                        depthCm: depth,
                        source: source
                    )
                }
            }

            if let context = self.clinicalContext {
                self.showWoundAssessment(scan: scan, patient: context.patient, wound: context.wound, manualMeasurements: manualMeasurements)
            } else {
                self.pendingManualMeasurements = manualMeasurements
                self.showPostScanAssignment(scan: scan)
            }
        }

        let viewController = MeasurementResultViewController(viewModel: viewModel)
        viewController.title = "Measurement Results"
        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - Step 4a: Post-Scan Patient Assignment (Quick Scan path)

    private func showPostScanAssignment(scan: WoundScan) {
        CrashLogger.shared.log("Navigating to Post-Scan Assignment", category: .coordinator)
        let assignmentVC = PostScanAssignmentViewController(storage: dependencies.clinicalStorage)

        assignmentVC.onAssigned = { [weak self] patient, wound in
            let manual = self?.pendingManualMeasurements
            self?.pendingManualMeasurements = nil
            self?.showWoundAssessment(scan: scan, patient: patient, wound: wound, manualMeasurements: manual)
        }

        assignmentVC.onSkip = { [weak self] in
            CrashLogger.shared.log("Skipped patient assignment — saving unassigned", category: .coordinator)
            self?.saveAndFinish(scan: scan)
        }

        navigationController.pushViewController(assignmentVC, animated: true)
    }

    // MARK: - Step 4b: Wound Assessment Form

    private func showWoundAssessment(scan: WoundScan, patient: Patient, wound: Wound, manualMeasurements: ManualMeasurements? = nil) {
        CrashLogger.shared.log("Navigating to Wound Assessment for \(patient.fullName) — \(wound.label)", category: .coordinator)
        let viewModel = WoundAssessmentViewModel(
            scan: scan,
            patient: patient,
            wound: wound,
            clinicalStorage: dependencies.clinicalStorage,
            scanStorage: dependencies.localStorage,
            uploadManager: dependencies.uploadManager,
            tokenStore: dependencies.clinicalPlatformKeychain,
            clinicalPlatformClient: dependencies.clinicalPlatformClient,
            manualMeasurementsFromResult: manualMeasurements
        )

        viewModel.onAssessmentComplete = { [weak self] _ in
            CrashLogger.shared.log("Assessment complete — flow finished", category: .coordinator)
            self?.finishFlow()
        }

        viewModel.onCancel = { [weak self] in
            self?.navigationController.popViewController(animated: true)
        }

        let viewController = WoundAssessmentViewController(viewModel: viewModel)
        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - Flow Completion

    private func saveAndFinish(scan: WoundScan) {
        Task { @MainActor in
            try? await dependencies.localStorage.saveScan(scan)
            await dependencies.uploadManager.enqueueUpload(scan: scan)
            finishFlow()
        }
    }

    private func finishFlow() {
        if let onFlowComplete {
            onFlowComplete()
        } else {
            showCapture()
        }
    }
}

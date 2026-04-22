import Foundation
import Combine
import ARKit
import WoundCore
import WoundCapture

// MARK: - V5 Capture View Model

/// ObservableObject driving the V5 SwiftUI capture screen.
/// Subscribes to LiDARCaptureSession publishers for real-time state.
final class V5CaptureViewModel: ObservableObject {

    // MARK: - Published State

    @Published var trackingState: TrackingState = .notAvailable
    @Published var readiness: CaptureReadiness = .notReady(reason: .trackingNotNormal)
    @Published var confidenceSummary: ConfidenceMapSummary?
    @Published var currentDistanceM: Float?
    @Published var error: String?

    // MARK: - Navigation

    var onCaptureComplete: ((CaptureBundle) -> Void)?

    // MARK: - Dependencies

    let captureSession: LiDARCaptureSession
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?

    // MARK: - Computed

    var isReadyToCapture: Bool { readiness.isReady }

    #if !targetEnvironment(simulator)
    var arSession: ARSession { captureSession.session }
    #endif

    var guidanceText: String {
        switch readiness {
        case .ready:
            if let d = currentDistanceM {
                return String(format: "Ready — %.0f cm", d * 100)
            }
            return "Ready"
        case .notReady(let reason):
            return reason.displayMessage
        }
    }

    var guidanceIconName: String {
        switch readiness {
        case .ready:
            return "checkmark.circle.fill"
        case .notReady(let reason):
            return reason.iconName
        }
    }

    // MARK: - Init

    init(captureSession: LiDARCaptureSession) {
        self.captureSession = captureSession
        setupBindings()
    }

    // MARK: - Session Lifecycle

    func startSession() {
        sessionStartTime = Date()
        do {
            try captureSession.startSession()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func pauseSession() {
        captureSession.pauseSession()
    }

    // MARK: - Capture

    func capture() {
        guard readiness.isReady else { return }
        do {
            let snapshot = try captureSession.captureSnapshot()

            let captureData = snapshot.toCaptureData(lidarAvailable: true)
            let qualityScore = captureSession.qualityMonitor.qualityScoreSnapshot(
                meshVertexCount: snapshot.vertices.count,
                meanDepthConfidence: 0,
                meshHitRate: 0
            )

            let confSummary: ConfidenceSummary
            if let summary = captureSession.currentConfidenceSummary() {
                confSummary = ConfidenceSummary(
                    highFraction: summary.highFraction,
                    mediumFraction: summary.mediumFraction,
                    lowFraction: summary.lowFraction
                )
            } else {
                confSummary = ConfidenceSummary(
                    fromConfidenceMap: snapshot.confidenceMap
                )
            }

            let bundle = CaptureBundle(
                captureData: captureData,
                captureMode: .singleShot,
                qualityScore: qualityScore,
                confidenceSummary: confSummary,
                sessionMetadata: CaptureSessionMetadata(
                    deviceModel: snapshot.deviceModel,
                    lidarAvailable: true,
                    trackingStableSeconds: captureSession.qualityMonitor.trackingStableSeconds,
                    captureDistanceM: captureSession.estimatedDistance ?? 0,
                    meshAnchorCount: captureSession.meshAnchorCount,
                    sessionDurationSeconds: captureSession.sessionDuration
                )
            )

            onCaptureComplete?(bundle)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        captureSession.onTrackingStateChanged = { [weak self] state in
            DispatchQueue.main.async { self?.trackingState = state }
        }

        captureSession.qualityMonitor.readinessPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] readiness in self?.readiness = readiness }
            .store(in: &cancellables)

        captureSession.distancePublisher
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] distance in self?.currentDistanceM = distance }
            .store(in: &cancellables)

        captureSession.confidencePublisher
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] summary in self?.confidenceSummary = summary }
            .store(in: &cancellables)
    }
}

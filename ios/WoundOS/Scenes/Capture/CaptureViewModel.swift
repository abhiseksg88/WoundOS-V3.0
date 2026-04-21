import Foundation
import Combine
import ARKit
import WoundCore
import WoundCapture

// MARK: - Capture View Model

/// Capture screen view model. Drives strict pre-capture gating
/// from the CaptureQualityMonitor's published readiness state.
final class CaptureViewModel: ObservableObject {

    // MARK: - Published State

    @Published var trackingState: TrackingState = .notAvailable
    @Published var readiness: CaptureReadiness = .notReady(reason: .trackingNotNormal)
    @Published var error: String?

    // MARK: - Navigation

    /// Provides both the snapshot and the moment-of-capture quality score.
    var onCaptureComplete: ((CaptureSnapshot, CaptureQualityScore?) -> Void)?

    // MARK: - Dependencies

    private let captureProvider: CaptureProviderProtocol
    private let qualityMonitor: CaptureQualityMonitor?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed

    var isLiDARAvailable: Bool {
        captureProvider.isLiDARAvailable
    }

    /// The underlying ARSession so the view controller can attach an ARSCNView.
    var arSession: ARSession? {
        #if targetEnvironment(simulator)
        return nil
        #else
        return (captureProvider as? ARSessionManager)?.session
        #endif
    }

    /// True when all four strict gates are satisfied.
    var isReadyToCapture: Bool {
        readiness.isReady
    }

    /// Human-readable guidance shown on the floating card.
    var guidanceText: String {
        switch readiness {
        case .ready:
            if let d = qualityMonitor?.lastDistance {
                return String(format: "Ready — %.0f cm", d * 100)
            }
            return "Ready"
        case .notReady(let reason):
            return reason.displayMessage
        }
    }

    /// SF Symbol icon name for the guidance card.
    var guidanceIconName: String {
        switch readiness {
        case .ready: return "checkmark.circle.fill"
        case .notReady(let reason): return reason.iconName
        }
    }

    // MARK: - Init

    init(captureProvider: CaptureProviderProtocol) {
        self.captureProvider = captureProvider
        self.qualityMonitor = (captureProvider as? ARSessionManager)?.qualityMonitor
        setupBindings()
    }

    // MARK: - Session Lifecycle

    func startSession() {
        CrashLogger.shared.log("Starting AR session", category: .capture)
        CrashLogger.shared.log("LiDAR available: \(isLiDARAvailable)", category: .capture)
        do {
            try captureProvider.startSession()
            CrashLogger.shared.log("AR session started successfully", category: .capture)
        } catch {
            CrashLogger.shared.error("AR session start failed", category: .capture, error: error)
            self.error = error.localizedDescription
        }
    }

    func pauseSession() {
        CrashLogger.shared.log("Pausing AR session", category: .capture)
        captureProvider.pauseSession()
    }

    // MARK: - Capture

    func capture() {
        // Strict gate enforcement at the call site too
        guard readiness.isReady else {
            CrashLogger.shared.log("Capture blocked — not ready: \(readiness)", category: .capture, level: .warning)
            return
        }
        CrashLogger.shared.log("Capture triggered — freezing AR frame", category: .capture)
        do {
            let snapshot = try captureProvider.captureSnapshot()
            CrashLogger.shared.log("Snapshot captured: \(snapshot.vertices.count) vertices, \(snapshot.faces.count) faces", category: .capture)
            // Stamp pre-capture quality info; mesh hit rate / depth confidence
            // get filled in by BoundaryDrawingViewModel after projection runs.
            let preQuality = qualityMonitor?.qualityScoreSnapshot(
                meshVertexCount: snapshot.vertices.count,
                meanDepthConfidence: 0,
                meshHitRate: 0
            )
            onCaptureComplete?(snapshot, preQuality)
        } catch {
            CrashLogger.shared.error("Capture snapshot failed", category: .capture, error: error)
            self.error = error.localizedDescription
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        captureProvider.onTrackingStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.trackingState = state
            }
        }

        // Subscribe to readiness updates from the strict quality monitor
        if let monitor = qualityMonitor {
            monitor.readinessPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] readiness in
                    self?.readiness = readiness
                }
                .store(in: &cancellables)
        }
    }
}

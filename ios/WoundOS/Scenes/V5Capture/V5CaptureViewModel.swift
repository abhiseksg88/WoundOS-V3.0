import Foundation
import Combine
import ARKit
import UIKit
import WoundCore
import WoundCapture

// MARK: - Quality Level

/// Visual state for the corner quality indicator.
enum CaptureQualityLevel: Equatable {
    case gray   // Initializing (tracking not normal, no distance)
    case amber  // Adjust needed (too far, too close, stabilizing, etc.)
    case green  // Ready to capture
}

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

    // GATE 2 smoke test — available in Release for TestFlight validation
    @Published var lastCaptureBundle: CaptureBundle?
    @Published var dumpToastMessage: String?

    // A1/A5: Heatmap reveal (long-press)
    @Published var isHeatmapRevealed = false

    // A2: Quality indicator
    @Published var qualityLevel: CaptureQualityLevel = .gray
    @Published var showQualityTooltip = false
    @Published var qualityTooltipText = ""

    // MARK: - Navigation

    var onCaptureComplete: ((CaptureBundle) -> Void)?

    // MARK: - Dependencies

    let captureSession: LiDARCaptureSession
    private var cancellables = Set<AnyCancellable>()
    private var sessionStartTime: Date?
    private var previousQualityLevel: CaptureQualityLevel = .gray

    // MARK: - Computed

    var isReadyToCapture: Bool { readiness.isReady }

    #if !targetEnvironment(simulator)
    var arSession: ARSession { captureSession.session }
    #endif

    var guidanceText: String {
        switch readiness {
        case .ready:
            if DeveloperMode.isEnabled, let d = currentDistanceM {
                return String(format: "Ready — %.0f cm", d * 100)
            }
            return "Ready to capture"
        case .notReady(let reason):
            return DeveloperMode.isEnabled ? reason.displayMessage : reason.cleanDisplayMessage
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

    /// Dynamic hint shown above capture button. Empty when ready (no hint needed).
    var distanceHintText: String {
        switch readiness {
        case .ready:
            return ""
        case .notReady(let reason):
            switch reason {
            case .tooClose:
                return "Move back slightly"
            case .tooFar(let d):
                return d > 0.50 ? "Much too far — move closer" : "Move closer for best capture"
            case .noDistance:
                return "Hold 20–35 cm from wound"
            default:
                return ""
            }
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

    func resumeSession() {
        do {
            try captureSession.resumeSession()
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

            lastCaptureBundle = bundle

            onCaptureComplete?(bundle)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func dumpBundle() {
        guard let bundle = lastCaptureBundle else { return }
        let output = bundle.debugDescription(verbose: true)
        print(output)

        // Write to file
        let filename = "capture_debug_\(bundle.id.uuidString).txt"
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsDir.appendingPathComponent(filename)
            try? output.write(to: fileURL, atomically: true, encoding: .utf8)
            dumpToastMessage = "Dumped to console + \(filename)"
        } else {
            dumpToastMessage = "Dumped to console (file write failed)"
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

        // A2/A4: Quality level derivation with debounce + haptic
        captureSession.qualityMonitor.readinessPublisher
            .map { readiness -> CaptureQualityLevel in
                switch readiness {
                case .ready:
                    return .green
                case .notReady(let reason):
                    switch reason {
                    case .trackingNotNormal, .noDistance:
                        return .gray
                    default:
                        return .amber
                    }
                }
            }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self else { return }
                // A4: Haptic on transition to green
                if level == .green && self.previousQualityLevel != .green {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                self.previousQualityLevel = self.qualityLevel
                self.qualityLevel = level

                // Update tooltip text
                switch level {
                case .gray:
                    self.qualityTooltipText = self.readiness == .notReady(reason: .noDistance)
                        ? "Point camera at wound" : "LiDAR warming up..."
                case .amber:
                    if case .notReady(let reason) = self.readiness {
                        self.qualityTooltipText = reason.cleanDisplayMessage
                    }
                case .green:
                    self.qualityTooltipText = "Ready to capture"
                }
            }
            .store(in: &cancellables)
    }
}

import Foundation
import Combine
import WoundCore
import WoundCapture

// MARK: - Capture View Model

final class CaptureViewModel: ObservableObject {

    // MARK: - Published State

    @Published var trackingState: TrackingState = .notAvailable
    @Published var estimatedDistance: Float?
    @Published var isReadyToCapture = false
    @Published var error: String?

    // MARK: - Navigation

    var onCaptureComplete: ((CaptureSnapshot) -> Void)?

    // MARK: - Dependencies

    private let captureProvider: CaptureProviderProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed

    var isLiDARAvailable: Bool {
        captureProvider.isLiDARAvailable
    }

    var distanceGuidance: String {
        guard let distance = estimatedDistance else {
            return "Move device closer to wound"
        }
        if distance < 0.10 {
            return "Too close — move back"
        } else if distance < 0.15 {
            return "Getting close — good"
        } else if distance <= 0.30 {
            return "Perfect distance (\(Int(distance * 100)) cm)"
        } else if distance <= 0.50 {
            return "Move closer to wound"
        } else {
            return "Too far — move much closer"
        }
    }

    var isOptimalDistance: Bool {
        guard let distance = estimatedDistance else { return false }
        return (0.15...0.30).contains(distance)
    }

    // MARK: - Init

    init(captureProvider: CaptureProviderProtocol) {
        self.captureProvider = captureProvider
        setupBindings()
    }

    // MARK: - Session Lifecycle

    func startSession() {
        do {
            try captureProvider.startSession()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func pauseSession() {
        captureProvider.pauseSession()
    }

    // MARK: - Capture

    func capture() {
        do {
            let snapshot = try captureProvider.captureSnapshot()
            onCaptureComplete?(snapshot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Bindings

    private func setupBindings() {
        captureProvider.onTrackingStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.trackingState = state
                if case .normal = state {
                    self?.isReadyToCapture = true
                } else {
                    self?.isReadyToCapture = false
                }
            }
        }

        // Poll distance from ARSessionManager
        if let arManager = captureProvider as? ARSessionManager {
            Timer.publish(every: 0.2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self, weak arManager] _ in
                    self?.estimatedDistance = arManager?.estimatedDistance
                }
                .store(in: &cancellables)
        }
    }
}

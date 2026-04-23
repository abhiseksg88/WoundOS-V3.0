import ARKit
import Combine
import simd
import WoundCore

// MARK: - Capture Readiness

/// Output of the quality monitor. Either ready to capture, or blocked
/// for a specific reason that can be displayed to the nurse.
public enum CaptureReadiness: Equatable {
    case ready
    case notReady(reason: BlockingReason)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Blocking Reason

/// Why the capture button is currently disabled.
/// Each case maps to a specific gate failing.
public enum BlockingReason: Equatable {
    case trackingNotNormal
    case trackingNotStable(elapsed: Double)
    case tooFar(distanceM: Float)
    case tooClose(distanceM: Float)
    case noDistance
    case insufficientMesh(vertexCount: Int)
    case excessiveMotion(angularVelocity: Double)

    public var displayMessage: String {
        switch self {
        case .trackingNotNormal:
            return "Initializing AR — hold device steady"
        case .trackingNotStable(let elapsed):
            return String(format: "Stabilizing… (%.1fs)", elapsed)
        case .tooFar(let d):
            return String(format: "Too far — move closer (%.0f cm)", d * 100)
        case .tooClose(let d):
            return String(format: "Too close — pull back (%.0f cm)", d * 100)
        case .noDistance:
            return "Point camera at wound"
        case .insufficientMesh(let count):
            return "Scanning surface… (\(count) pts)"
        case .excessiveMotion:
            return "Hold device still"
        }
    }

    /// Production-facing guidance text without raw metrics.
    /// Used when DeveloperMode is OFF for a clean clinical experience.
    public var cleanDisplayMessage: String {
        switch self {
        case .trackingNotNormal:
            return "Initializing — hold steady"
        case .trackingNotStable:
            return "Stabilizing..."
        case .tooFar:
            return "Move closer"
        case .tooClose:
            return "Pull back slightly"
        case .noDistance:
            return "Point camera at wound"
        case .insufficientMesh:
            return "Scanning surface..."
        case .excessiveMotion:
            return "Hold device still"
        }
    }

    public var iconName: String {
        switch self {
        case .trackingNotNormal, .trackingNotStable: return "arkit"
        case .tooFar, .tooClose, .noDistance:        return "ruler"
        case .insufficientMesh:                       return "square.stack.3d.up"
        case .excessiveMotion:                        return "hand.raised"
        }
    }
}

// MARK: - Capture Quality Monitor

/// Apple Measure-style strict gating. Watches every AR frame and
/// publishes whether the capture button should be enabled.
///
/// All four gates must pass:
/// 1. Tracking state is `.normal` for ≥ stableThreshold seconds
/// 2. Distance to surface in optimalDistance range
/// 3. Mesh has ≥ minMeshVertices in the central viewport region
/// 4. Angular velocity below maxAngularVelocity (device steady)
public final class CaptureQualityMonitor {

    // MARK: - Configuration

    public struct Configuration {
        public var optimalDistance: ClosedRange<Float> = 0.15...0.30
        public var stableThreshold: TimeInterval = 1.5
        public var minMeshVertices: Int = 500
        public var maxAngularVelocity: Double = 0.05
        public var motionWindowSeconds: TimeInterval = 0.5

        public static let `default` = Configuration()
    }

    // MARK: - Public API

    public let readinessPublisher = PassthroughSubject<CaptureReadiness, Never>()

    public private(set) var currentReadiness: CaptureReadiness = .notReady(reason: .trackingNotNormal) {
        didSet {
            if currentReadiness != oldValue {
                readinessPublisher.send(currentReadiness)
            }
        }
    }

    public private(set) var lastDistance: Float?
    public private(set) var lastVertexCount: Int = 0
    public private(set) var lastAngularVelocity: Double = 0

    /// Time the tracking state has continuously been `.normal`.
    public var trackingStableSeconds: Double {
        guard let trackingNormalSince else { return 0 }
        return Date().timeIntervalSince(trackingNormalSince)
    }

    // MARK: - Internal State

    private var configuration: Configuration
    private var trackingNormalSince: Date?
    private var rotationSamples: [(Date, simd_float3)] = []
    private var lastEulerAngles: simd_float3?

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Frame Update

    /// Called by ARSessionManager on every frame. Updates internal state
    /// and re-evaluates readiness.
    public func update(frame: ARFrame, meshAnchorVertexCount: Int) {
        // 1. Tracking state
        let isNormalTracking: Bool
        switch frame.camera.trackingState {
        case .normal:
            isNormalTracking = true
            if trackingNormalSince == nil {
                trackingNormalSince = Date()
            }
        default:
            isNormalTracking = false
            trackingNormalSince = nil
        }

        // 2. Distance estimate
        lastDistance = estimateDistance(from: frame)

        // 3. Mesh vertex count (provided by caller — already consolidated)
        lastVertexCount = meshAnchorVertexCount

        // 4. Angular velocity from camera transform
        lastAngularVelocity = updateMotionEstimate(from: frame)

        // Evaluate gates in order — first failure short-circuits
        currentReadiness = evaluate(
            isNormalTracking: isNormalTracking,
            distance: lastDistance,
            meshVertexCount: lastVertexCount,
            angularVelocity: lastAngularVelocity
        )
    }

    // MARK: - Gate Evaluation

    private func evaluate(
        isNormalTracking: Bool,
        distance: Float?,
        meshVertexCount: Int,
        angularVelocity: Double
    ) -> CaptureReadiness {

        // Gate 1: Tracking
        guard isNormalTracking else {
            return .notReady(reason: .trackingNotNormal)
        }

        let stableElapsed = trackingStableSeconds
        guard stableElapsed >= configuration.stableThreshold else {
            return .notReady(reason: .trackingNotStable(elapsed: stableElapsed))
        }

        // Gate 2: Distance
        guard let distance, distance > 0 else {
            return .notReady(reason: .noDistance)
        }
        if distance < configuration.optimalDistance.lowerBound {
            return .notReady(reason: .tooClose(distanceM: distance))
        }
        if distance > configuration.optimalDistance.upperBound {
            return .notReady(reason: .tooFar(distanceM: distance))
        }

        // Gate 3: Mesh density
        guard meshVertexCount >= configuration.minMeshVertices else {
            return .notReady(reason: .insufficientMesh(vertexCount: meshVertexCount))
        }

        // Gate 4: Motion stability
        guard angularVelocity < configuration.maxAngularVelocity else {
            return .notReady(reason: .excessiveMotion(angularVelocity: angularVelocity))
        }

        return .ready
    }

    // MARK: - Distance Estimation

    private func estimateDistance(from frame: ARFrame) -> Float? {
        guard let depth = frame.smoothedSceneDepth?.depthMap else { return nil }

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depth)

        // Sample a 5x5 grid around the center and take the median
        var samples = [Float]()
        let cx = width / 2
        let cy = height / 2
        let step = max(1, min(width, height) / 20)

        for dy in -2...2 {
            for dx in -2...2 {
                let row = cy + dy * step
                let col = cx + dx * step
                guard row >= 0, row < height, col >= 0, col < width else { continue }
                let ptr = base.advanced(by: row * bytesPerRow)
                    .assumingMemoryBound(to: Float32.self)
                let value = ptr[col]
                if value > 0 && value.isFinite {
                    samples.append(value)
                }
            }
        }

        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    // MARK: - Motion Estimation

    /// Estimate angular velocity from camera euler angle changes.
    private func updateMotionEstimate(from frame: ARFrame) -> Double {
        let euler = frame.camera.eulerAngles
        let now = Date()

        defer {
            lastEulerAngles = euler
            rotationSamples.append((now, euler))
            // Trim to motion window
            let cutoff = now.addingTimeInterval(-configuration.motionWindowSeconds)
            rotationSamples.removeAll { $0.0 < cutoff }
        }

        guard let last = lastEulerAngles else { return 0 }
        let delta = euler - last
        let magnitude = simd_length(delta)
        return Double(magnitude)
    }

    // MARK: - Quality Score

    /// Build a quality score for the moment of capture.
    public func qualityScoreSnapshot(
        meshVertexCount: Int,
        meanDepthConfidence: Double,
        meshHitRate: Double
    ) -> CaptureQualityScore {
        CaptureQualityScore(
            trackingStableSeconds: trackingStableSeconds,
            captureDistanceM: Double(lastDistance ?? 0),
            meshVertexCount: meshVertexCount,
            meanDepthConfidence: meanDepthConfidence,
            meshHitRate: meshHitRate,
            angularVelocityRadPerSec: lastAngularVelocity
        )
    }

    // MARK: - Reset

    public func reset() {
        trackingNormalSince = nil
        rotationSamples.removeAll()
        lastEulerAngles = nil
        lastDistance = nil
        lastVertexCount = 0
        lastAngularVelocity = 0
        currentReadiness = .notReady(reason: .trackingNotNormal)
    }
}

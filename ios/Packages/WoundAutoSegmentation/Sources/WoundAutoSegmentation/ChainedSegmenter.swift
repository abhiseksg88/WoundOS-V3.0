import CoreGraphics
import Foundation

// MARK: - Fallback Reason

/// Why the ChainedSegmenter fell back from CoreML to server.
/// Stored in telemetry for deployment monitoring.
public enum SegmenterFallbackReason: String, Sendable {
    /// CoreML model failed to load (missing or corrupt).
    case coremlLoadFailed = "coreml_load_failed"
    /// Canary validation failed (IoU below threshold).
    case canaryFailed = "canary_failed"
    /// CoreML inference threw an error at runtime.
    case coremlInferenceFailed = "coreml_inference_failed"
}

// MARK: - Chained Segmenter

/// Routes between an on-device CoreML segmenter (primary) and a server
/// segmenter (fallback) with automatic degradation.
///
/// Routing logic:
/// 1. If `primary` is nil (model not bundled) → fallback immediately.
/// 2. On first call, run canary validator (lazy, one-shot).
/// 3. If canary fails → permanent fallback for this session.
/// 4. Try primary; if it throws → fallback for this call.
/// 5. Primary success → return result directly.
///
/// The `modelIdentifier` in the returned `SegmentationResult` naturally
/// indicates which backend was used (each segmenter sets its own identifier).
public final class ChainedSegmenter: WoundSegmenter {

    private let primary: WoundSegmenter?
    private let fallback: WoundSegmenter
    private let canaryValidator: CoreMLCanaryValidator?

    /// Tracks canary state: nil = not yet run, true = passed, false = failed.
    private var canaryPassed: Bool?
    private let lock = NSLock()

    /// Last canary result for telemetry reporting.
    public private(set) var lastCanaryResult: CanaryResult?

    /// Why the most recent call fell back to server. Nil if primary was used.
    public private(set) var lastFallbackReason: SegmenterFallbackReason?

    public init(
        primary: WoundSegmenter?,
        fallback: WoundSegmenter,
        canaryValidator: CoreMLCanaryValidator?
    ) {
        self.primary = primary
        self.fallback = fallback
        self.canaryValidator = canaryValidator
    }

    public func segment(
        image: CGImage,
        tapPoint: CGPoint
    ) async throws -> SegmentationResult {

        // 1. No primary segmenter → straight to fallback
        guard let primary else {
            lastFallbackReason = .coremlLoadFailed
            return try await fallback.segment(image: image, tapPoint: tapPoint)
        }

        // 2. Run canary on first call (lazy, one-shot)
        let canaryState = getCanaryState()
        if canaryState == nil {
            await runCanary()
        }

        // 3. If canary failed → permanent fallback
        if getCanaryState() == false {
            lastFallbackReason = .canaryFailed
            return try await fallback.segment(image: image, tapPoint: tapPoint)
        }

        // 4. Try primary (CoreML)
        do {
            let result = try await primary.segment(image: image, tapPoint: tapPoint)
            lastFallbackReason = nil
            return result
        } catch {
            // 5. CoreML failed → fallback for this call
            lastFallbackReason = .coremlInferenceFailed
            return try await fallback.segment(image: image, tapPoint: tapPoint)
        }
    }

    // MARK: - Canary Management

    private func getCanaryState() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return canaryPassed
    }

    private func setCanaryState(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        canaryPassed = value
    }

    private func runCanary() async {
        guard let validator = canaryValidator else {
            // No validator → skip canary, assume pass
            setCanaryState(true)
            return
        }

        do {
            let result = try await validator.validate()
            lastCanaryResult = result
            setCanaryState(result.passed)
        } catch {
            // Canary itself threw → treat as failure
            setCanaryState(false)
        }
    }
}

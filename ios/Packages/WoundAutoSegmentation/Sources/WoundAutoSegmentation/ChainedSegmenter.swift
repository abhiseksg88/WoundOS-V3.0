import CoreGraphics
import Foundation
import os

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

    private static let logger = Logger(
        subsystem: "com.woundos.segmentation",
        category: "ChainedSegmenter"
    )

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
        let log = Self.logger

        log.info("segment: entry, has_primary=\(self.primary != nil), canary_state=\(String(describing: self.getCanaryState()))")

        // 1. No primary segmenter → straight to fallback
        guard let primary else {
            lastFallbackReason = .coremlLoadFailed
            log.warning("segment: no primary → fallback (coreml_load_failed)")
            return try await fallback.segment(image: image, tapPoint: tapPoint)
        }

        // 2. Run canary on first call (lazy, one-shot)
        let canaryState = getCanaryState()
        if canaryState == nil {
            log.info("segment: running canary (first call)")
            await runCanary()
        }

        // 3. If canary failed → permanent fallback
        if getCanaryState() == false {
            lastFallbackReason = .canaryFailed
            let iou = lastCanaryResult.map { String(format: "%.4f", $0.iou) } ?? "nil"
            log.warning("segment: canary failed (iou=\(iou)) → permanent fallback")
            return try await fallback.segment(image: image, tapPoint: tapPoint)
        }

        // 4. Try primary (CoreML)
        log.info("segment: attempting primary (CoreML)")
        do {
            let result = try await primary.segment(image: image, tapPoint: tapPoint)
            lastFallbackReason = nil
            log.info("segment: primary succeeded, confidence=\(String(format: "%.2f", result.confidence)), latency=\(String(format: "%.0f", result.inferenceLatencyMs))ms")
            return result
        } catch {
            // 5. CoreML failed → fallback for this call
            lastFallbackReason = .coremlInferenceFailed
            log.error("segment: primary threw \(error.localizedDescription) → fallback")
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
        let log = Self.logger
        guard let validator = canaryValidator else {
            // No validator → skip canary, assume pass
            setCanaryState(true)
            log.info("canary: no validator configured, skipping (assume pass)")
            return
        }

        do {
            let result = try await validator.validate()
            lastCanaryResult = result
            setCanaryState(result.passed)
            log.info("canary: passed=\(result.passed), iou=\(String(format: "%.4f", result.iou)), expected_px=\(result.expectedPositivePixels), actual_px=\(result.actualPositivePixels), latency=\(String(format: "%.0f", result.latencyMs))ms")

            // Persist canary result to telemetry store for debug screen survival across restarts
            let canaryRecord = SegmentationTelemetryRecord(
                segmenterIdentifier: "canary.coreml",
                inferenceLatencyMs: result.latencyMs,
                rawConfidence: Float(result.iou),
                rawCoveragePct: 0,
                rawAspectRatio: 0,
                rawComponentCount: 0,
                qualityResult: result.passed ? "canary_passed" : "canary_failed",
                qualityDetail: "iou=\(String(format: "%.4f", result.iou)), expected=\(result.expectedPositivePixels), actual=\(result.actualPositivePixels)",
                onDeviceFlagState: true,
                canaryIoU: Float(result.iou),
                canaryPassed: result.passed,
                chainedSegmenterUsed: true,
                isCanaryRecord: true
            )
            SegmentationTelemetryStore.shared.record(canaryRecord)
        } catch {
            // Canary itself threw → treat as failure
            setCanaryState(false)
            log.error("canary: threw error → marking failed: \(error.localizedDescription)")

            // Persist canary failure to telemetry
            let failRecord = SegmentationTelemetryRecord(
                segmenterIdentifier: "canary.coreml",
                inferenceLatencyMs: 0,
                rawConfidence: 0,
                rawCoveragePct: 0,
                rawAspectRatio: 0,
                rawComponentCount: 0,
                qualityResult: "canary_error",
                qualityDetail: error.localizedDescription,
                onDeviceFlagState: true,
                canaryPassed: false,
                chainedSegmenterUsed: true,
                isCanaryRecord: true
            )
            SegmentationTelemetryStore.shared.record(failRecord)
        }
    }
}

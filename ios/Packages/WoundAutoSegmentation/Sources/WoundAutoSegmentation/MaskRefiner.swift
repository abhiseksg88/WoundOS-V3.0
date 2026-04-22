import CoreVideo
import Foundation

// MARK: - Mask Refinement Context

/// Contextual metadata passed to a mask refiner to inform its processing.
/// Does not contain PHI — only device/capture context.
public struct MaskRefinementContext: Sendable {
    public let capturedAt: Date
    public let deviceModel: String
    public let captureDistanceMeters: Float
    public let lidarConfidencePercent: Float

    public init(
        capturedAt: Date,
        deviceModel: String,
        captureDistanceMeters: Float,
        lidarConfidencePercent: Float
    ) {
        self.capturedAt = capturedAt
        self.deviceModel = deviceModel
        self.captureDistanceMeters = captureDistanceMeters
        self.lidarConfidencePercent = lidarConfidencePercent
    }
}

// MARK: - Mask Refinement Errors

public enum MaskRefinementError: Error, LocalizedError {
    case networkRequired
    case refinerUnavailable(reason: String)
    case refinementFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .networkRequired:
            return "Network connection required for mask refinement."
        case .refinerUnavailable(let reason):
            return "Mask refiner unavailable: \(reason)"
        case .refinementFailed(let underlying):
            return "Mask refinement failed: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Mask Refiner Protocol

/// V6 extension point for cloud-based or on-device mask refinement.
///
/// After segmentation produces a mask, the refiner can improve it
/// (e.g., WoundAmbit cloud refiner, edge-aware CRF). For V5, the
/// `IdentityMaskRefiner` is a no-op pass-through with zero runtime cost.
public protocol MaskRefiner: Sendable {
    var identifier: String { get }
    var requiresNetwork: Bool { get }

    func refine(
        mask: SegmentationResult,
        context: MaskRefinementContext
    ) async throws -> SegmentationResult
}

// MARK: - Identity Mask Refiner (No-Op)

/// Pass-through refiner that returns the input mask unchanged.
/// Default for V5 — ensures the refiner call site exists without
/// adding latency or complexity.
public struct IdentityMaskRefiner: MaskRefiner {
    public let identifier = "identity.v1"
    public let requiresNetwork = false

    public init() {}

    public func refine(
        mask: SegmentationResult,
        context: MaskRefinementContext
    ) async throws -> SegmentationResult {
        return mask
    }
}

import CoreGraphics
import Foundation

// MARK: - Mask Rejection Reasons

/// Specific reason why a segmentation mask was rejected by the quality gate.
/// Each reason maps to a user-facing message in the boundary drawing UI.
public enum MaskRejectionReason: String, Codable, Equatable {
    case coverageTooSmall
    case coverageTooLarge
    case frameEdgeContact
    case aspectRatioInvalid
    case disconnectedComponents
    case confidenceTooLow
    case degeneratePolygon
}

// MARK: - Quality Result

/// Outcome of running a segmentation result through the quality gate.
public enum MaskQualityResult: Equatable {
    case accept
    case reject(reason: MaskRejectionReason, detail: String)

    public var isAccepted: Bool {
        if case .accept = self { return true }
        return false
    }

    public var rejectionReason: MaskRejectionReason? {
        if case .reject(let reason, _) = self { return reason }
        return nil
    }

    public var rejectionDetail: String? {
        if case .reject(_, let detail) = self { return detail }
        return nil
    }
}

// MARK: - Quality Thresholds

/// Tunable thresholds for the mask quality gate.
/// Single struct so thresholds can be adjusted post-TestFlight without
/// scattering magic numbers across files.
public struct MaskQualityThresholds {

    /// Minimum polygon area / frame area. Below this the detection is noise.
    /// 1% = roughly 40×30 pixels in a 4032×3024 frame.
    public let minCoverageFraction: Double

    /// Maximum polygon area / frame area. Above this the detection grabbed
    /// the entire foreground (arm, table, etc.), not just the wound.
    public let maxCoverageFraction: Double

    /// Minimum bounding box aspect ratio (short/long). Below 0.15 = thin stripe.
    public let minAspectRatio: Double

    /// Maximum bounding box aspect ratio (short/long). Above 6.67 = unusually wide.
    public let maxAspectRatio: Double

    /// Minimum model confidence. Below 0.5 = model is guessing.
    public let minConfidence: Float

    /// Minimum vertex count for a valid polygon.
    public let minVertexCount: Int

    /// Maximum connected components in the binary mask.
    /// More than 1 means the mask has disjoint regions.
    public let maxConnectedComponents: Int

    /// Frame edge margin in normalized coords (0...1).
    /// If the polygon bbox extends within this margin of ALL 4 edges,
    /// it's likely a full-frame false positive.
    public let frameEdgeMargin: Double

    public init(
        minCoverageFraction: Double = 0.01,
        maxCoverageFraction: Double = 0.40,
        minAspectRatio: Double = 0.15,
        maxAspectRatio: Double = 6.67,
        minConfidence: Float = 0.5,
        minVertexCount: Int = 3,
        maxConnectedComponents: Int = 1,
        frameEdgeMargin: Double = 0.03
    ) {
        self.minCoverageFraction = minCoverageFraction
        self.maxCoverageFraction = maxCoverageFraction
        self.minAspectRatio = minAspectRatio
        self.maxAspectRatio = maxAspectRatio
        self.minConfidence = minConfidence
        self.minVertexCount = minVertexCount
        self.maxConnectedComponents = maxConnectedComponents
        self.frameEdgeMargin = frameEdgeMargin
    }

    public static let `default` = MaskQualityThresholds()
}

// MARK: - Mask Quality Gate

/// Stateless evaluator that decides whether a segmentation result is clinically
/// usable. Returns the first failing check with a specific reason.
///
/// The gate is intentionally lenient — tuned so that a well-framed credit card
/// close-up (which worked in Phase 2) still passes. Edge cases are rejected
/// with actionable user messages.
public struct MaskQualityGate {

    /// Evaluate a segmentation result against quality thresholds.
    ///
    /// Checks run in order of cheapest to most expensive. Returns the
    /// first failure so the UI can show a specific, actionable message.
    public static func evaluate(
        polygon: [CGPoint],
        imageSize: CGSize,
        confidence: Float,
        connectedComponents: Int,
        thresholds: MaskQualityThresholds = .default
    ) -> MaskQualityResult {

        // 1. Degenerate polygon (< 3 vertices)
        guard polygon.count >= thresholds.minVertexCount else {
            return .reject(
                reason: .degeneratePolygon,
                detail: "Polygon has \(polygon.count) vertices (minimum \(thresholds.minVertexCount))"
            )
        }

        // 2. Confidence check
        guard confidence >= thresholds.minConfidence else {
            return .reject(
                reason: .confidenceTooLow,
                detail: String(format: "Confidence %.2f < minimum %.2f", confidence, thresholds.minConfidence)
            )
        }

        // 3. Coverage check (shoelace area / frame area)
        let frameArea = Double(imageSize.width) * Double(imageSize.height)
        guard frameArea > 0 else {
            return .reject(reason: .degeneratePolygon, detail: "Image size is zero")
        }
        let polyArea = abs(shoelaceArea(polygon))
        let coverage = polyArea / frameArea

        if coverage < thresholds.minCoverageFraction {
            return .reject(
                reason: .coverageTooSmall,
                detail: String(format: "Coverage %.2f%% < minimum %.0f%%", coverage * 100, thresholds.minCoverageFraction * 100)
            )
        }
        if coverage > thresholds.maxCoverageFraction {
            return .reject(
                reason: .coverageTooLarge,
                detail: String(format: "Coverage %.1f%% > maximum %.0f%%", coverage * 100, thresholds.maxCoverageFraction * 100)
            )
        }

        // 4. Bounding box aspect ratio
        let bbox = boundingBox(polygon)
        let shortSide = min(bbox.width, bbox.height)
        let longSide = max(bbox.width, bbox.height)
        let aspectRatio = longSide > 0 ? Double(shortSide) / Double(longSide) : 0

        if aspectRatio < thresholds.minAspectRatio {
            return .reject(
                reason: .aspectRatioInvalid,
                detail: String(format: "Aspect ratio %.3f < minimum %.2f", aspectRatio, thresholds.minAspectRatio)
            )
        }
        // For max aspect ratio, compare long/short (inverse)
        let inverseAspect = shortSide > 0 ? Double(longSide) / Double(shortSide) : .infinity
        if inverseAspect > thresholds.maxAspectRatio {
            return .reject(
                reason: .aspectRatioInvalid,
                detail: String(format: "Aspect ratio %.2f:1 > maximum %.2f:1", inverseAspect, thresholds.maxAspectRatio)
            )
        }

        // 5. Frame edge contact — bbox touches all 4 edges within margin
        let margin = thresholds.frameEdgeMargin
        let normBBox = CGRect(
            x: Double(bbox.minX) / Double(imageSize.width),
            y: Double(bbox.minY) / Double(imageSize.height),
            width: Double(bbox.width) / Double(imageSize.width),
            height: Double(bbox.height) / Double(imageSize.height)
        )
        let touchesLeft = normBBox.minX < margin
        let touchesTop = normBBox.minY < margin
        let touchesRight = normBBox.maxX > (1.0 - margin)
        let touchesBottom = normBBox.maxY > (1.0 - margin)

        if touchesLeft && touchesTop && touchesRight && touchesBottom {
            return .reject(
                reason: .frameEdgeContact,
                detail: "Detection spans the entire frame"
            )
        }

        // 6. Connected components
        if connectedComponents > thresholds.maxConnectedComponents {
            return .reject(
                reason: .disconnectedComponents,
                detail: "\(connectedComponents) regions detected (maximum \(thresholds.maxConnectedComponents))"
            )
        }

        return .accept
    }

    // MARK: - User-Facing Messages

    /// Maps a rejection reason to an actionable user-facing message.
    public static func userMessage(for reason: MaskRejectionReason) -> String {
        switch reason {
        case .coverageTooSmall:
            return "Detected area too small. Move closer or use Draw Manually."
        case .coverageTooLarge:
            return "Detected area too large. Frame only the wound or use Draw Manually."
        case .frameEdgeContact:
            return "Could not isolate wound. Reframe or use Draw Manually."
        case .aspectRatioInvalid:
            return "Detected shape is unusual. Try a different angle or use Draw Manually."
        case .disconnectedComponents:
            return "Multiple regions detected. Reframe or use Draw Manually."
        case .confidenceTooLow:
            return "Not confident this is a wound. Try Draw Manually."
        case .degeneratePolygon:
            return "Segmentation failed. Try again or use Draw Manually."
        }
    }

    // MARK: - Geometry Helpers

    /// Shoelace formula for polygon area in pixel coordinates.
    private static func shoelaceArea(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var area: Double = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += Double(points[i].x) * Double(points[j].y)
            area -= Double(points[j].x) * Double(points[i].y)
        }
        return area / 2.0
    }

    /// Axis-aligned bounding box of a polygon.
    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

import Foundation
import simd
import WoundCore

// MARK: - Validation Severity

public enum ValidationSeverity {
    case warning
    case error
}

// MARK: - Boundary Validation Result

public struct BoundaryValidationResult {
    public let isValid: Bool
    public let errors: [BoundaryValidationError]

    public static let valid = BoundaryValidationResult(isValid: true, errors: [])
}

public enum BoundaryValidationError: Error, LocalizedError {
    case tooFewPoints(count: Int)
    case selfIntersecting
    case areaTooSmall(areaPx2: Double)
    case boundaryOutOfBounds

    public var errorDescription: String? {
        switch self {
        case .tooFewPoints(let count):
            return "Need at least 3 points to form a boundary (have \(count))"
        case .selfIntersecting:
            return "Polygon looks like it crosses itself — measurement may be inaccurate"
        case .areaTooSmall(let area):
            return "Polygon looks small (\(Int(area)) px²) — measurement may be inaccurate"
        case .boundaryOutOfBounds:
            return "Boundary extends outside the captured image"
        }
    }

    /// All validation issues are non-blocking warnings (Bug 7).
    /// The Measure button should never be gated on these.
    public var severity: ValidationSeverity {
        switch self {
        case .tooFewPoints:
            return .error   // Truly invalid — can't form a polygon
        case .selfIntersecting, .areaTooSmall, .boundaryOutOfBounds:
            return .warning
        }
    }
}

// MARK: - Boundary Validator

/// Validates that a nurse-drawn boundary is geometrically sound
/// before proceeding to 3D projection and measurement.
public enum BoundaryValidator {

    /// Minimum number of boundary points
    public static let minimumPointCount = 3

    /// Minimum enclosed area in normalized coordinate units squared
    public static let minimumNormalizedArea: Double = 0.0001

    /// Validate a set of 2D boundary points (normalized 0...1 coordinates).
    /// Only `tooFewPoints` makes the result truly invalid. All other issues
    /// are non-blocking warnings (Bug 7 fix).
    public static func validate(points: [SIMD2<Float>]) -> BoundaryValidationResult {
        var errors = [BoundaryValidationError]()

        // Check minimum point count — this is the only truly blocking check
        if points.count < minimumPointCount {
            errors.append(.tooFewPoints(count: points.count))
            return BoundaryValidationResult(isValid: false, errors: errors)
        }

        // Check bounds (all points within 0...1)
        let outOfBounds = points.contains { p in
            p.x < -0.01 || p.x > 1.01 || p.y < -0.01 || p.y > 1.01
        }
        if outOfBounds {
            errors.append(.boundaryOutOfBounds)
        }

        // Check for self-intersection (warning only)
        if isSelfIntersecting(points) {
            errors.append(.selfIntersecting)
        }

        // Check minimum area using shoelace formula (warning only)
        let area = polygonArea(points)
        if area < minimumNormalizedArea {
            errors.append(.areaTooSmall(areaPx2: area * 1_000_000))
        }

        // isValid is true as long as we have enough points — other issues
        // are surfaced as warnings but don't block measurement.
        return BoundaryValidationResult(
            isValid: true,
            errors: errors
        )
    }

    // MARK: - Self-Intersection Check

    /// Check if any two non-adjacent edges of the polygon intersect.
    /// Capped at 50 points to avoid O(n²) blowup — larger polygons
    /// (typically from auto-segmentation) are assumed well-formed.
    static func isSelfIntersecting(_ points: [SIMD2<Float>]) -> Bool {
        let n = points.count
        guard n >= 4, n <= 50 else { return false }

        for i in 0..<n {
            let a1 = points[i]
            let a2 = points[(i + 1) % n]

            for j in (i + 2)..<n {
                // Skip adjacent edges
                if j == (i + n - 1) % n { continue }

                let b1 = points[j]
                let b2 = points[(j + 1) % n]

                if segmentsIntersect(a1, a2, b1, b2) {
                    return true
                }
            }
        }
        return false
    }

    /// Test if two line segments intersect using cross products.
    private static func segmentsIntersect(
        _ a1: SIMD2<Float>, _ a2: SIMD2<Float>,
        _ b1: SIMD2<Float>, _ b2: SIMD2<Float>
    ) -> Bool {
        let d1 = crossProduct2D(a2 - a1, b1 - a1)
        let d2 = crossProduct2D(a2 - a1, b2 - a1)
        let d3 = crossProduct2D(b2 - b1, a1 - b1)
        let d4 = crossProduct2D(b2 - b1, a2 - b1)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        // Check collinear cases
        if abs(d1) < 1e-10 && onSegment(a1, b1, a2) { return true }
        if abs(d2) < 1e-10 && onSegment(a1, b2, a2) { return true }
        if abs(d3) < 1e-10 && onSegment(b1, a1, b2) { return true }
        if abs(d4) < 1e-10 && onSegment(b1, a2, b2) { return true }

        return false
    }

    private static func crossProduct2D(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        a.x * b.y - a.y * b.x
    }

    private static func onSegment(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>) -> Bool {
        q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) &&
        q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)
    }

    // MARK: - Polygon Area (Shoelace)

    /// Compute area of a polygon using the shoelace formula.
    /// Returns unsigned area in the coordinate system of the input points.
    public static func polygonArea(_ points: [SIMD2<Float>]) -> Double {
        guard points.count >= 3 else { return 0 }

        var area: Double = 0
        let n = points.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += Double(points[i].x) * Double(points[j].y)
            area -= Double(points[j].x) * Double(points[i].y)
        }

        return abs(area) / 2.0
    }
}

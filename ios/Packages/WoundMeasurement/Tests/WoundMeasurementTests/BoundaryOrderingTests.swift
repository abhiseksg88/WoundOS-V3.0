import XCTest
import simd
@testable import WoundMeasurement

/// Tests for boundary polygon ordering and its impact on area computation.
///
/// Root cause: when boundary points arrive in an order that makes the polygon
/// self-intersect (bowtie/figure-8), MeshClipper's winding-number containment
/// test identifies only the small interior lobes → fewer mesh triangles are
/// clipped → area is undercounted.
///
/// Fix: angular sort around centroid before clipping eliminates self-intersections.
final class BoundaryOrderingTests: XCTestCase {

    // MARK: - Test 1: Shuffled Rectangle

    /// ISO/IEC 7810 credit card: 85.60 × 53.98 mm = 46.22 cm².
    /// Boundary points in shuffled order (not perimeter traversal).
    /// After ordering, 2D polygon area must be 46.22 cm² ± 2%.
    func testShuffledRectangle_areaAfterOrdering() {
        // Card corners in meters (flat in XY plane)
        let w: Float = 0.0856  // 85.6mm
        let h: Float = 0.05398 // 53.98mm

        // Correct CCW corners
        let tl = SIMD2<Float>(0, h)
        let tr = SIMD2<Float>(w, h)
        let br = SIMD2<Float>(w, 0)
        let bl = SIMD2<Float>(0, 0)

        // Shuffled: not going around the perimeter (creates self-intersection)
        let shuffled = [tl, br, tr, bl]

        // Before ordering: shoelace on self-intersecting polygon gives wrong area
        let areaBefore = ProjectionUtils.polygonArea2D(shuffled)
        let areaBeforeCm2 = Double(areaBefore) * 10_000.0

        // After ordering: angular sort fixes winding
        let ordered = ProjectionUtils.orderPointsCounterClockwise(shuffled)
        let areaAfter = ProjectionUtils.polygonArea2D(ordered)
        let areaAfterCm2 = Double(areaAfter) * 10_000.0

        let expected = 46.22 // cm²

        // Before ordering, area should be significantly wrong
        XCTAssertTrue(areaBeforeCm2 < expected * 0.5,
                      "Shuffled area (\(areaBeforeCm2) cm²) should be much less than \(expected) cm²")

        // After ordering, area must be correct
        XCTAssertEqual(areaAfterCm2, expected, accuracy: expected * 0.02,
                       "Ordered area should be \(expected) cm² ± 2%, got \(areaAfterCm2) cm²")
    }

    // MARK: - Test 2: Self-Intersecting Bowtie

    /// Four points ordered as [TL, BR, TR, BL] forming a bowtie (X shape).
    /// Before ordering → area is very small (just the two small triangular lobes).
    /// After ordering → area equals the full quadrilateral.
    func testBowtie_areaBeforeAndAfterOrdering() {
        // 10cm × 10cm square → 100 cm²
        let side: Float = 0.1

        let tl = SIMD2<Float>(0, side)
        let tr = SIMD2<Float>(side, side)
        let br = SIMD2<Float>(side, 0)
        let bl = SIMD2<Float>(0, 0)

        // Bowtie order: TL → BR → TR → BL (edges cross in the middle)
        let bowtie = [tl, br, tr, bl]
        let bowtieCm2 = Double(ProjectionUtils.polygonArea2D(bowtie)) * 10_000.0

        // Proper CCW order
        let ordered = ProjectionUtils.orderPointsCounterClockwise(bowtie)
        let orderedCm2 = Double(ProjectionUtils.polygonArea2D(ordered)) * 10_000.0

        // Bowtie area should be nearly zero (the two triangular lobes partially cancel)
        XCTAssertTrue(bowtieCm2 < 10.0,
                      "Bowtie area (\(bowtieCm2) cm²) should be very small")

        // After ordering, full square area
        XCTAssertEqual(orderedCm2, 100.0, accuracy: 1.0,
                       "Ordered area should be 100 cm², got \(orderedCm2) cm²")
    }

    // MARK: - Test 3: Clean Rectangle (Idempotent)

    /// Points already in correct CCW order.
    /// Ordering step must not change the area (idempotent on correct input).
    func testCleanRectangle_orderingIsIdempotent() {
        let w: Float = 0.0856
        let h: Float = 0.05398

        // Already in CCW order: BL → BR → TR → TL
        let ccw = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(w, 0),
            SIMD2<Float>(w, h),
            SIMD2<Float>(0, h),
        ]

        let areaBefore = ProjectionUtils.polygonArea2D(ccw)
        let ordered = ProjectionUtils.orderPointsCounterClockwise(ccw)
        let areaAfter = ProjectionUtils.polygonArea2D(ordered)

        // Must be identical (within floating point)
        XCTAssertEqual(Double(areaBefore) * 10_000.0,
                       Double(areaAfter) * 10_000.0,
                       accuracy: 0.01,
                       "Ordering a clean polygon must not change area")

        // Both should be 46.22 cm²
        let expected = 46.22
        XCTAssertEqual(Double(areaAfter) * 10_000.0, expected, accuracy: expected * 0.01,
                       "Clean rectangle area should be \(expected) cm²")
    }

    // MARK: - Test 4: Shuffled Circle

    /// 36 points on a radius-5cm circle in shuffled order.
    /// After ordering, area must be πr² = 78.54 cm² ± 3%.
    func testShuffledCircle_areaAfterOrdering() {
        let radius: Float = 0.05 // 5cm in meters
        let numPoints = 36
        var points = [SIMD2<Float>]()

        // Generate points in CCW order first
        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            points.append(SIMD2<Float>(
                radius * cos(angle),
                radius * sin(angle)
            ))
        }

        // Shuffle: reverse the second half to create self-intersection.
        // First half goes CCW, second half goes CW → polygon collapses.
        let half = numPoints / 2
        var shuffled = Array(points[0..<half]) + Array(points[half...].reversed())

        // Before ordering: self-intersecting polygon gives near-zero area
        let areaBefore = Double(ProjectionUtils.polygonArea2D(shuffled)) * 10_000.0

        // After ordering: angular sort restores circular winding
        let ordered = ProjectionUtils.orderPointsCounterClockwise(shuffled)
        let areaAfter = Double(ProjectionUtils.polygonArea2D(ordered)) * 10_000.0

        let expected = Double.pi * 25.0 // π × r² = π × 5² = 78.54 cm²

        // Before ordering, area should be near zero (self-intersecting collapse)
        XCTAssertTrue(areaBefore < expected * 0.1,
                      "Shuffled circle area (\(areaBefore) cm²) should be near zero")

        // After ordering, area ≈ πr²
        XCTAssertEqual(areaAfter, expected, accuracy: expected * 0.03,
                       "Ordered circle area should be \(expected) cm² ± 3%, got \(areaAfter) cm²")
    }

    // MARK: - Test 5: MeshClipper Containment Impact

    /// Proves that a self-intersecting boundary causes MeshClipper to classify
    /// interior points as outside, directly reducing clipped area.
    func testMeshClipper_bowtieExcludesInteriorPoints() {
        let side: Float = 0.1

        let tl = SIMD2<Float>(0, side)
        let tr = SIMD2<Float>(side, side)
        let br = SIMD2<Float>(side, 0)
        let bl = SIMD2<Float>(0, 0)

        // Bowtie order: TL → BR → TR → BL (edges cross forming figure-8)
        let bowtie = [tl, br, tr, bl]

        // Proper CCW order
        let ccw = ProjectionUtils.orderPointsCounterClockwise(bowtie)

        // Test point (0.02, 0.02) — clearly inside the square but outside the
        // bowtie's small lobes (which are near top-right and bottom-left quadrants)
        let testPoint = SIMD2<Float>(0.02, 0.02)

        // With bowtie: point falls outside the bowtie lobes → classified as OUTSIDE
        let insideBowtie = MeshClipper.isPointInPolygon(testPoint, polygon: bowtie)

        // With proper CCW: point is correctly INSIDE the square
        let insideCCW = MeshClipper.isPointInPolygon(testPoint, polygon: ccw)

        XCTAssertFalse(insideBowtie,
                       "Point should be OUTSIDE bowtie polygon (winding number = 0)")
        XCTAssertTrue(insideCCW,
                       "Point should be INSIDE properly-ordered polygon")
    }

    // MARK: - Test 6: Convex Hull Area Comparison (Task 3 diagnostic)

    /// For a rectangular boundary, sorted polygon area should be ≥ 85% of convex hull area.
    func testConvexHullAreaComparison() {
        let w: Float = 0.0856
        let h: Float = 0.05398

        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(w, 0),
            SIMD2<Float>(w, h),
            SIMD2<Float>(0, h),
        ]

        let sorted = ProjectionUtils.orderPointsCounterClockwise(points)
        let sortedArea = ProjectionUtils.polygonArea2D(sorted)

        let hull = ProjectionUtils.convexHull(points)
        let hullArea = ProjectionUtils.polygonArea2D(hull)

        let ratio = sortedArea / hullArea
        XCTAssertGreaterThanOrEqual(ratio, 0.85,
            "Sorted polygon area / convex hull area should be ≥ 0.85, got \(ratio)")
    }
}

import XCTest
import simd
@testable import WoundMeasurement

final class DepthCalculatorTests: XCTestCase {

    // MARK: - Flat Surface (No Depth)

    func testDepth_flatSurface_zeroDepth() {
        // All boundary and interior points on the same plane (z=0)
        // Expected: max depth = 0, mean depth = 0
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0.1, 0, 0),
            SIMD3<Float>(0.1, 0.1, 0),
            SIMD3<Float>(0, 0.1, 0),
        ]

        let interior: [SIMD3<Float>] = [
            SIMD3<Float>(0.03, 0.03, 0),
            SIMD3<Float>(0.05, 0.05, 0),
            SIMD3<Float>(0.07, 0.07, 0),
        ]

        // Camera is above the plane
        let camera = SIMD3<Float>(0.05, 0.05, 0.3)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.maxDepthMm, 0, accuracy: 0.1)
        XCTAssertEqual(result!.meanDepthMm, 0, accuracy: 0.1)
    }

    // MARK: - Known Depth (Bowl Shape)

    func testDepth_syntheticBowl_knownDepth() {
        // Boundary: square on z=0 plane (the wound rim)
        // Interior: points at z = -0.01 (1cm below rim)
        // Expected: max depth ≈ 10mm, mean depth ≈ 10mm
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(-0.05, -0.05, 0),
            SIMD3<Float>( 0.05, -0.05, 0),
            SIMD3<Float>( 0.05,  0.05, 0),
            SIMD3<Float>(-0.05,  0.05, 0),
        ]

        // Interior points all at z = -0.01 (10mm below rim)
        let interior: [SIMD3<Float>] = [
            SIMD3<Float>(-0.02, -0.02, -0.01),
            SIMD3<Float>( 0.00,  0.00, -0.01),
            SIMD3<Float>( 0.02,  0.02, -0.01),
            SIMD3<Float>(-0.01,  0.01, -0.01),
            SIMD3<Float>( 0.01, -0.01, -0.01),
            SIMD3<Float>( 0.03,  0.00, -0.01),
            SIMD3<Float>(-0.03,  0.00, -0.01),
            SIMD3<Float>( 0.00,  0.03, -0.01),
            SIMD3<Float>( 0.00, -0.03, -0.01),
            SIMD3<Float>( 0.02, -0.02, -0.01),
        ]

        // Camera above the plane (z positive)
        let camera = SIMD3<Float>(0, 0, 0.3)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNotNil(result)
        // All interior points are 10mm below the boundary plane
        XCTAssertEqual(result!.maxDepthMm, 10.0, accuracy: 0.5)
        XCTAssertEqual(result!.meanDepthMm, 10.0, accuracy: 0.5)
        XCTAssertEqual(result!.belowPlaneCount, 10)
        XCTAssertEqual(result!.abovePlaneCount, 0)
        XCTAssertTrue(result!.isReliable)
    }

    // MARK: - Graded Depth (Varying z)

    func testDepth_gradedBowl_maxAndMean() {
        // Boundary: square on z=0
        // Interior: points at varying depths below rim
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(-0.05, -0.05, 0),
            SIMD3<Float>( 0.05, -0.05, 0),
            SIMD3<Float>( 0.05,  0.05, 0),
            SIMD3<Float>(-0.05,  0.05, 0),
        ]

        // 5 points at -5mm, 5 points at -15mm → mean ~10mm, max ~15mm
        var interior: [SIMD3<Float>] = []
        for i in 0..<5 {
            let x = Float(i) * 0.01 - 0.02
            interior.append(SIMD3<Float>(x, 0, -0.005))  // 5mm deep
        }
        for i in 0..<5 {
            let x = Float(i) * 0.01 - 0.02
            interior.append(SIMD3<Float>(x, 0.01, -0.015))  // 15mm deep
        }

        let camera = SIMD3<Float>(0, 0, 0.3)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.maxDepthMm, 15.0, accuracy: 0.5)
        XCTAssertEqual(result!.meanDepthMm, 10.0, accuracy: 0.5)
        XCTAssertTrue(result!.isReliable)
    }

    // MARK: - Reliability

    func testDepth_unreliable_tooFewBelowPlane() {
        // Boundary: square on z=0
        // Interior: only 5 points below (< 10 threshold)
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(-0.05, -0.05, 0),
            SIMD3<Float>( 0.05, -0.05, 0),
            SIMD3<Float>( 0.05,  0.05, 0),
            SIMD3<Float>(-0.05,  0.05, 0),
        ]

        let interior: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, -0.01),
            SIMD3<Float>(0.01, 0, -0.01),
            SIMD3<Float>(-0.01, 0, -0.01),
            SIMD3<Float>(0, 0.01, -0.01),
            SIMD3<Float>(0, -0.01, -0.01),
        ]

        let camera = SIMD3<Float>(0, 0, 0.3)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isReliable,
                       "Should be unreliable with < 10 below-plane vertices")
    }

    func testDepth_unreliable_tooManyAbovePlane() {
        // Boundary: square on z=0
        // Interior: mix of above and below, with > 30% above
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(-0.05, -0.05, 0),
            SIMD3<Float>( 0.05, -0.05, 0),
            SIMD3<Float>( 0.05,  0.05, 0),
            SIMD3<Float>(-0.05,  0.05, 0),
        ]

        // 10 below, 6 above → 37.5% above
        var interior: [SIMD3<Float>] = []
        for i in 0..<10 {
            let x = Float(i) * 0.005 - 0.025
            interior.append(SIMD3<Float>(x, 0, -0.01))   // below
        }
        for i in 0..<6 {
            let x = Float(i) * 0.005 - 0.015
            interior.append(SIMD3<Float>(x, 0.01, 0.005))  // above
        }

        let camera = SIMD3<Float>(0, 0, 0.3)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isReliable,
                       "Should be unreliable with > 30% above-plane vertices")
    }

    // MARK: - Edge Cases

    func testDepth_insufficientBoundaryPoints() {
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
        ]
        let interior: [SIMD3<Float>] = [SIMD3<Float>(0.5, 0, -0.01)]
        let camera = SIMD3<Float>(0, 0, 1)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNil(result, "Should return nil with < 3 boundary points")
    }

    func testDepth_emptyInterior_zeroDepth() {
        let boundary: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0.1, 0, 0),
            SIMD3<Float>(0.05, 0.1, 0),
        ]
        let interior: [SIMD3<Float>] = []
        let camera = SIMD3<Float>(0, 0, 1)

        let result = DepthCalculator.computeDepth(
            boundaryPoints3D: boundary,
            interiorVertices: interior,
            cameraPosition: camera
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.maxDepthMm, 0, accuracy: 0.01)
        XCTAssertEqual(result!.meanDepthMm, 0, accuracy: 0.01)
    }
}

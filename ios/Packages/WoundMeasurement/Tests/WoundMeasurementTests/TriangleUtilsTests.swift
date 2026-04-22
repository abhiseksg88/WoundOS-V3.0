import XCTest
import simd
@testable import WoundMeasurement

final class TriangleUtilsTests: XCTestCase {

    // MARK: - Triangle Area

    func testTriangleArea_unitRightTriangle() {
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(1, 0, 0)
        let v2 = SIMD3<Float>(0, 1, 0)

        let area = TriangleUtils.triangleArea(v0, v1, v2)
        XCTAssertEqual(area, 0.5, accuracy: 1e-6)
    }

    func testTriangleArea_equilateral() {
        // Equilateral triangle with side length 2
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(2, 0, 0)
        let v2 = SIMD3<Float>(1, sqrt(3.0), 0)

        let area = TriangleUtils.triangleArea(v0, v1, v2)
        let expected: Float = sqrt(3.0)  // side² × √3/4 = 4 × √3/4
        XCTAssertEqual(area, expected, accuracy: 1e-5)
    }

    func testTriangleArea_3D() {
        // Triangle in 3D space
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(1, 0, 0)
        let v2 = SIMD3<Float>(0, 0, 1)

        let area = TriangleUtils.triangleArea(v0, v1, v2)
        XCTAssertEqual(area, 0.5, accuracy: 1e-6)
    }

    func testTriangleArea_degenerate() {
        // Collinear points → zero area
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(1, 0, 0)
        let v2 = SIMD3<Float>(2, 0, 0)

        let area = TriangleUtils.triangleArea(v0, v1, v2)
        XCTAssertEqual(area, 0, accuracy: 1e-6)
    }

    // MARK: - Centroid

    func testTriangleCentroid() {
        let v0 = SIMD3<Float>(0, 0, 0)
        let v1 = SIMD3<Float>(3, 0, 0)
        let v2 = SIMD3<Float>(0, 3, 0)

        let centroid = TriangleUtils.triangleCentroid(v0, v1, v2)
        XCTAssertEqual(centroid.x, 1.0, accuracy: 1e-6)
        XCTAssertEqual(centroid.y, 1.0, accuracy: 1e-6)
        XCTAssertEqual(centroid.z, 0.0, accuracy: 1e-6)
    }

    // MARK: - Plane Fitting

    func testFitPlane_flatSquare() {
        // Four points in the XY plane at z=0.5
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0.5),
            SIMD3<Float>(1, 0, 0.5),
            SIMD3<Float>(1, 1, 0.5),
            SIMD3<Float>(0, 1, 0.5),
        ]

        guard let plane = TriangleUtils.fitPlane(to: points) else {
            XCTFail("Plane fitting returned nil")
            return
        }

        // Normal should be along Z axis
        XCTAssertEqual(abs(plane.normal.z), 1.0, accuracy: 1e-4)
        XCTAssertEqual(plane.point.z, 0.5, accuracy: 1e-6)
    }

    func testFitPlane_tilted() {
        // Points on the plane z = x (45-degree tilt)
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 1),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(1, 1, 1),
        ]

        guard let plane = TriangleUtils.fitPlane(to: points) else {
            XCTFail("Plane fitting returned nil")
            return
        }

        // Normal should be perpendicular to the plane z = x
        // Expected normal: (-1, 0, 1) / sqrt(2) or (1, 0, -1) / sqrt(2)
        let dot = simd_dot(plane.normal, SIMD3<Float>(1, 0, -1).normalized)
        XCTAssertTrue(abs(dot) > 0.99, "Normal should be along (1, 0, -1) direction")
    }

    // MARK: - Signed Distance to Plane

    func testSignedDistanceToPlane() {
        let planePoint = SIMD3<Float>(0, 0, 0)
        let planeNormal = SIMD3<Float>(0, 0, 1)  // Z-up plane

        let above = TriangleUtils.signedDistanceToPlane(
            point: SIMD3<Float>(0, 0, 5),
            planePoint: planePoint,
            planeNormal: planeNormal
        )
        XCTAssertEqual(above, 5.0, accuracy: 1e-6)

        let below = TriangleUtils.signedDistanceToPlane(
            point: SIMD3<Float>(0, 0, -3),
            planePoint: planePoint,
            planeNormal: planeNormal
        )
        XCTAssertEqual(below, -3.0, accuracy: 1e-6)

        let onPlane = TriangleUtils.signedDistanceToPlane(
            point: SIMD3<Float>(5, 5, 0),
            planePoint: planePoint,
            planeNormal: planeNormal
        )
        XCTAssertEqual(onPlane, 0.0, accuracy: 1e-6)
    }

    // MARK: - Signed Tetrahedron Volume

    func testSignedTetrahedronVolume_unitCube() {
        // One tetrahedron of a unit cube
        let v0 = SIMD3<Float>(1, 0, 0)
        let v1 = SIMD3<Float>(0, 1, 0)
        let v2 = SIMD3<Float>(0, 0, 1)

        let volume = TriangleUtils.signedTetrahedronVolume(v0, v1, v2)
        XCTAssertEqual(abs(volume), 1.0 / 6.0, accuracy: 1e-6)
    }
}

// MARK: - SIMD3 normalized helper

private extension SIMD3 where Scalar == Float {
    var normalized: SIMD3<Float> {
        simd_normalize(self)
    }
}

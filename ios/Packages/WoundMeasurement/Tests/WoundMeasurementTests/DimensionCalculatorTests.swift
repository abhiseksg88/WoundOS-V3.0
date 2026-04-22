import XCTest
import simd
@testable import WoundMeasurement

/// Tests for DimensionCalculator verifying rotating calipers produces
/// correct length/width for various geometries — including curved surfaces.
/// The π-factor investigation: if a cylindrical boundary gives length = π × diameter,
/// the bug is in the dimension calculator.
final class DimensionCalculatorTests: XCTestCase {

    // MARK: - Flat Rectangle

    /// 3cm × 1cm rectangle in the XY plane.
    /// Expected: length ≈ 30mm, width ≈ 10mm
    func testFlatRectangle() {
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(-0.015, -0.005, 0),
            SIMD3<Float>( 0.015, -0.005, 0),
            SIMD3<Float>( 0.015,  0.005, 0),
            SIMD3<Float>(-0.015,  0.005, 0),
        ]
        let planePoint = SIMD3<Float>(0, 0, 0)
        let planeNormal = SIMD3<Float>(0, 0, 1)

        let result = DimensionCalculator.computeDimensions(
            boundaryPoints3D: points,
            referencePlanePoint: planePoint,
            referencePlaneNormal: planeNormal
        )

        XCTAssertEqual(result.lengthMm, 30.0, accuracy: 1.0, "Length of 3cm rectangle")
        XCTAssertEqual(result.widthMm, 10.0, accuracy: 1.0, "Width of 1cm rectangle")
    }

    // MARK: - Flat Circle

    /// Circle with diameter 15cm (radius 7.5cm) in the XY plane.
    /// 100 points uniformly distributed.
    /// Expected: length ≈ width ≈ 150mm (the diameter, NOT π×diameter)
    func testFlatCircle_diameterNotCircumference() {
        let radius: Float = 0.075  // 7.5cm in meters
        let numPoints = 100
        var points = [SIMD3<Float>]()

        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            points.append(SIMD3<Float>(
                radius * cos(angle),
                radius * sin(angle),
                0
            ))
        }

        let planePoint = SIMD3<Float>(0, 0, 0)
        let planeNormal = SIMD3<Float>(0, 0, 1)

        let result = DimensionCalculator.computeDimensions(
            boundaryPoints3D: points,
            referencePlanePoint: planePoint,
            referencePlaneNormal: planeNormal
        )

        let diameter: Double = 150.0  // 15cm in mm
        let circumference = Double.pi * diameter  // 471.2mm — this is the WRONG answer

        // Length MUST be the diameter (~150mm), NOT the circumference (~471mm)
        XCTAssertEqual(result.lengthMm, diameter, accuracy: 5.0,
                       "Circle length should be diameter (150mm), not circumference (\(circumference)mm)")
        XCTAssertEqual(result.widthMm, diameter, accuracy: 5.0,
                       "Circle width should be diameter (150mm)")

        // Verify it's NOT the circumference
        XCTAssertTrue(result.lengthMm < circumference * 0.5,
                      "Length (\(result.lengthMm)mm) must NOT be near circumference (\(circumference)mm)")
    }

    // MARK: - Cylindrical Surface

    /// Boundary points on the front hemisphere of a cylinder (15cm diameter).
    /// Simulates what BoundaryProjector produces when tracing a circular boundary
    /// on a cylindrical can viewed from the front.
    /// Expected: length ≈ width ≈ 150mm (the DIAMETER, not circumference)
    func testCylinderFrontHemisphere_diameterNotCircumference() {
        let radius: Float = 0.075  // 7.5cm
        let numPoints = 100
        var points = [SIMD3<Float>]()

        // Points on the front hemisphere of a cylinder (axis along Y)
        // viewed from +Z direction. θ ranges from -90° to 90° (front half).
        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            // In the image, this traces a circle.
            // On the cylinder surface, x = r·sin(angle), z = r·cos(angle)
            // But only the front hemisphere is visible (z > 0 face of cylinder)
            // For the full outline, left edge = (-r, y, 0), right edge = (r, y, 0),
            // top/bottom = (0, ±h/2, r)
            // Approximate: distribute points around the visible boundary
            let theta = Float(i) * (.pi / Float(numPoints)) - .pi / 2  // -90° to 90°
            let x = radius * sin(angle)     // full circle in image x
            let y = radius * cos(angle)     // full circle in image y
            let z = radius * cos(theta)     // curved surface depth
            points.append(SIMD3<Float>(x, y, z))
        }

        let planePoint = TriangleUtils.polygonCentroid(points)
        guard let plane = TriangleUtils.fitPlane(to: points) else {
            XCTFail("Plane fit failed")
            return
        }

        let result = DimensionCalculator.computeDimensions(
            boundaryPoints3D: points,
            referencePlanePoint: planePoint,
            referencePlaneNormal: plane.normal
        )

        let diameter: Double = 150.0  // 15cm in mm
        let circumference = Double.pi * diameter

        // Length should be approximately the diameter, NOT the circumference
        XCTAssertEqual(result.lengthMm, diameter, accuracy: 20.0,
                       "Cylinder length should be ~diameter (\(diameter)mm), got \(result.lengthMm)mm")
        XCTAssertTrue(result.lengthMm < circumference * 0.8,
                      "Length (\(result.lengthMm)mm) must NOT be near circumference (\(circumference)mm) — π factor bug!")
    }

    // MARK: - Realistic Can Boundary

    /// Simulates a 15cm-diameter, 15cm-tall can viewed from the front.
    /// Boundary traces the rectangular outline in the image, hits the curved
    /// mesh surface in 3D. Tests that the DimensionCalculator gives the
    /// actual physical dimensions, not π×.
    func testCanBoundary_physicalDimensions() {
        let radius: Float = 0.075   // 7.5cm diameter
        let halfHeight: Float = 0.075  // 15cm tall
        let numPointsPerEdge = 25
        var points = [SIMD3<Float>]()

        // Left silhouette: x = -r, z ≈ 0, y varies
        for i in 0..<numPointsPerEdge {
            let t = Float(i) / Float(numPointsPerEdge - 1)
            let y = -halfHeight + t * 2 * halfHeight
            points.append(SIMD3<Float>(-radius, y, 0))
        }

        // Top edge: y = halfHeight, traces the front surface
        for i in 0..<numPointsPerEdge {
            let t = Float(i) / Float(numPointsPerEdge - 1)
            let theta = -.pi / 2 + t * .pi  // -90° to 90°
            let x = radius * sin(theta)
            let z = radius * cos(theta)
            points.append(SIMD3<Float>(x, halfHeight, z))
        }

        // Right silhouette: x = r, z ≈ 0, y varies (top to bottom)
        for i in 0..<numPointsPerEdge {
            let t = Float(i) / Float(numPointsPerEdge - 1)
            let y = halfHeight - t * 2 * halfHeight
            points.append(SIMD3<Float>(radius, y, 0))
        }

        // Bottom edge: y = -halfHeight, traces the front surface
        for i in 0..<numPointsPerEdge {
            let t = Float(i) / Float(numPointsPerEdge - 1)
            let theta = .pi / 2 - t * .pi  // 90° to -90°
            let x = radius * sin(theta)
            let z = radius * cos(theta)
            points.append(SIMD3<Float>(x, -halfHeight, z))
        }

        let planePoint = TriangleUtils.polygonCentroid(points)
        guard let plane = TriangleUtils.fitPlane(to: points) else {
            XCTFail("Plane fit failed")
            return
        }

        // Orient normal toward camera (at +z)
        var normal = plane.normal
        let cameraPos = SIMD3<Float>(0, 0, 0.3)
        if simd_dot(normal, cameraPos - planePoint) < 0 {
            normal = -normal
        }

        let result = DimensionCalculator.computeDimensions(
            boundaryPoints3D: points,
            referencePlanePoint: planePoint,
            referencePlaneNormal: normal
        )

        // Physical dimensions: 15cm × 15cm
        let expectedDimension: Double = 150.0  // mm

        // Both length and width should be ~150mm
        // They MUST NOT be ~471mm (π × 150)
        XCTAssertEqual(result.lengthMm, expectedDimension, accuracy: 30.0,
                       "Can length should be ~\(expectedDimension)mm, got \(result.lengthMm)mm")
        XCTAssertEqual(result.widthMm, expectedDimension, accuracy: 30.0,
                       "Can width should be ~\(expectedDimension)mm, got \(result.widthMm)mm")

        // Explicit π-factor check
        let piDimension = Double.pi * expectedDimension
        XCTAssertTrue(result.lengthMm < piDimension * 0.5,
                      "LENGTH HAS π FACTOR: \(result.lengthMm)mm ≈ π × \(expectedDimension)mm = \(piDimension)mm")
        XCTAssertTrue(result.widthMm < piDimension * 0.5,
                      "WIDTH HAS π FACTOR: \(result.widthMm)mm ≈ π × \(expectedDimension)mm = \(piDimension)mm")
    }

    // MARK: - Dense SAM2-like Polygon

    /// SAM 2 can return 100-500 point polygons.
    /// Test that high-density circular boundaries don't confuse the rotating calipers.
    func testDenseSAM2Polygon_circleNotInflated() {
        let radius: Float = 0.05  // 5cm radius = 10cm diameter
        let numPoints = 400  // Dense polygon like SAM 2
        var points = [SIMD3<Float>]()

        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            points.append(SIMD3<Float>(
                radius * cos(angle),
                radius * sin(angle),
                0
            ))
        }

        let result = DimensionCalculator.computeDimensions(
            boundaryPoints3D: points,
            referencePlanePoint: .zero,
            referencePlaneNormal: SIMD3<Float>(0, 0, 1)
        )

        let diameter: Double = 100.0  // 10cm = 100mm
        XCTAssertEqual(result.lengthMm, diameter, accuracy: 3.0,
                       "Dense circle length should be diameter (\(diameter)mm)")
        XCTAssertEqual(result.widthMm, diameter, accuracy: 3.0,
                       "Dense circle width should be diameter (\(diameter)mm)")
    }
}

import XCTest
import simd
@testable import WoundMeasurement

final class PerimeterCalculatorTests: XCTestCase {

    func testPerimeter_square_40mm() {
        // A 1cm × 1cm square (0.01m sides)
        // Perimeter = 4 × 10mm = 40mm
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0.01, 0, 0),
            SIMD3<Float>(0.01, 0.01, 0),
            SIMD3<Float>(0, 0.01, 0),
        ]

        let perimeter = PerimeterCalculator.computePerimeter(points3D: points)
        XCTAssertEqual(perimeter, 40.0, accuracy: 0.1)
    }

    func testPerimeter_equilateralTriangle() {
        // Equilateral triangle with side 0.02m (20mm)
        // Perimeter = 60mm
        let side: Float = 0.02
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(side, 0, 0),
            SIMD3<Float>(side / 2, side * sqrt(3.0) / 2, 0),
        ]

        let perimeter = PerimeterCalculator.computePerimeter(points3D: points)
        XCTAssertEqual(perimeter, 60.0, accuracy: 0.5)
    }

    func testPerimeter_tooFewPoints() {
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
        ]
        XCTAssertEqual(PerimeterCalculator.computePerimeter(points3D: points), 0)
    }

    func testPerimeter_3D_notFlat() {
        // Triangle in 3D space — perimeter should account for 3D distances
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0.01, 0, 0),
            SIMD3<Float>(0.005, 0, 0.01),
        ]

        let perimeter = PerimeterCalculator.computePerimeter(points3D: points)
        XCTAssertGreaterThan(perimeter, 0)
    }

    // MARK: - Synthetic Circle Tests

    func testPerimeter_syntheticCircle_radius10cm() {
        // Circle with radius 0.1m (10cm), 360 points (1° per point)
        // Expected perimeter = 2πr = 2π × 100mm ≈ 628.32mm
        let radius: Float = 0.1  // 10cm in meters
        let numPoints = 360
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(numPoints)

        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            points.append(SIMD3<Float>(
                radius * cos(angle),
                radius * sin(angle),
                0
            ))
        }

        let perimeter = PerimeterCalculator.computePerimeter(points3D: points)
        let expected = 2.0 * Double.pi * 100.0  // 628.32mm
        // Smoothed circle should be within 5% of theoretical
        XCTAssertEqual(perimeter, expected, accuracy: expected * 0.05,
                       "Circle perimeter should be within 5% of 2πr")
    }

    func testPerimeter_syntheticCircle_rawVsSmoothed() {
        // Clean circle: smoothing should NOT significantly change a well-sampled circle
        let radius: Float = 0.1
        let numPoints = 360
        var points: [SIMD3<Float>] = []
        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            points.append(SIMD3<Float>(radius * cos(angle), radius * sin(angle), 0))
        }

        let raw = PerimeterCalculator.computeRawPerimeter(points3D: points)
        let smoothed = PerimeterCalculator.computePerimeter(points3D: points)

        // Smoothing a clean circle should change it by less than 2%
        let diff = abs(raw - smoothed)
        XCTAssertLessThan(diff / raw, 0.02,
                          "Smoothing a clean circle should not change perimeter by more than 2%")
    }

    func testPerimeter_noisyCircle_smoothingReduces() {
        // Circle with added noise — smoothing should reduce the perimeter
        let radius: Float = 0.1
        let numPoints = 180
        var points: [SIMD3<Float>] = []

        // Deterministic pseudo-noise: alternate +/- 5mm radial offset
        for i in 0..<numPoints {
            let angle = Float(i) * (2 * .pi / Float(numPoints))
            let noise: Float = (i % 2 == 0) ? 0.005 : -0.005  // ±5mm
            let r = radius + noise
            points.append(SIMD3<Float>(r * cos(angle), r * sin(angle), 0))
        }

        let raw = PerimeterCalculator.computeRawPerimeter(points3D: points)
        let smoothed = PerimeterCalculator.computePerimeter(points3D: points)

        // Smoothing should reduce the noisy perimeter
        XCTAssertLessThan(smoothed, raw,
                          "Smoothing should reduce perimeter on noisy boundary")

        // Smoothed should be closer to the ideal perimeter
        let expected = 2.0 * Double.pi * 100.0  // 628.32mm
        let rawError = abs(raw - expected)
        let smoothedError = abs(smoothed - expected)
        XCTAssertLessThan(smoothedError, rawError,
                          "Smoothed perimeter should be closer to ideal than raw")
    }

    // MARK: - Smoothing Unit Tests

    func testSmoothBoundary_preservesCount() {
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(1, 1, 0),
            SIMD3<Float>(0, 1, 0),
        ]

        let smoothed = PerimeterCalculator.smoothBoundary(points)
        XCTAssertEqual(smoothed.count, points.count,
                       "Smoothing should preserve point count")
    }

    func testSmoothBoundary_tooFewPoints() {
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
        ]
        let smoothed = PerimeterCalculator.smoothBoundary(points)
        XCTAssertEqual(smoothed.count, 2, "Should return input unchanged for < 3 points")
    }
}

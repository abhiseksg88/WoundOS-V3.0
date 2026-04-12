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
}

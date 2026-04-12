import XCTest
import simd
@testable import WoundMeasurement

final class AreaCalculatorTests: XCTestCase {

    // MARK: - Known Area Computations

    func testArea_singleTriangle_1cm2() {
        // A right triangle with legs of 0.01m (1cm) each
        // Area = 0.5 × 0.01 × 0.01 = 0.00005 m² = 0.5 cm²
        let vertices: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0.01, 0, 0),
            SIMD3<Float>(0, 0.01, 0),
        ]
        let faces: [(Int, Int, Int)] = [(0, 1, 2)]

        let area = AreaCalculator.computeArea(vertices: vertices, faces: faces)
        XCTAssertEqual(area, 0.5, accuracy: 0.01) // 0.5 cm²
    }

    func testArea_square_4cm2() {
        // A 2cm × 2cm square (0.02m × 0.02m) composed of two triangles
        // Area = 4 cm²
        let vertices: [SIMD3<Float>] = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(0.02, 0, 0),
            SIMD3<Float>(0.02, 0.02, 0),
            SIMD3<Float>(0, 0.02, 0),
        ]
        let faces: [(Int, Int, Int)] = [
            (0, 1, 2),
            (0, 2, 3),
        ]

        let area = AreaCalculator.computeArea(vertices: vertices, faces: faces)
        XCTAssertEqual(area, 4.0, accuracy: 0.01) // 4 cm²
    }

    func testArea_fromClippedMesh() {
        // ClippedMesh with known surface area
        let mesh = ClippedMesh(
            vertices: [],
            faces: [],
            surfaceAreaM2: 0.0012  // 12 cm²
        )
        let area = AreaCalculator.computeArea(clippedMesh: mesh)
        XCTAssertEqual(area, 12.0, accuracy: 0.01)
    }

    func testArea_emptyMesh() {
        let mesh = ClippedMesh(vertices: [], faces: [], surfaceAreaM2: 0)
        let area = AreaCalculator.computeArea(clippedMesh: mesh)
        XCTAssertEqual(area, 0)
    }
}

import XCTest
import simd
@testable import WoundMeasurement

final class MeshClipperTests: XCTestCase {

    // MARK: - Point-in-Polygon

    func testPointInPolygon_squareBoundary() {
        let square: [SIMD2<Float>] = [
            SIMD2<Float>(0.2, 0.2),
            SIMD2<Float>(0.8, 0.2),
            SIMD2<Float>(0.8, 0.8),
            SIMD2<Float>(0.2, 0.8),
        ]

        // Center — inside
        XCTAssertTrue(MeshClipper.isPointInPolygon(SIMD2<Float>(0.5, 0.5), polygon: square))

        // Corner region — inside
        XCTAssertTrue(MeshClipper.isPointInPolygon(SIMD2<Float>(0.3, 0.3), polygon: square))

        // Outside — left
        XCTAssertFalse(MeshClipper.isPointInPolygon(SIMD2<Float>(0.1, 0.5), polygon: square))

        // Outside — above
        XCTAssertFalse(MeshClipper.isPointInPolygon(SIMD2<Float>(0.5, 0.1), polygon: square))

        // Outside — far away
        XCTAssertFalse(MeshClipper.isPointInPolygon(SIMD2<Float>(1.5, 1.5), polygon: square))
    }

    func testPointInPolygon_triangleBoundary() {
        let triangle: [SIMD2<Float>] = [
            SIMD2<Float>(0.5, 0.1),
            SIMD2<Float>(0.9, 0.9),
            SIMD2<Float>(0.1, 0.9),
        ]

        // Center of triangle — inside
        XCTAssertTrue(MeshClipper.isPointInPolygon(SIMD2<Float>(0.5, 0.6), polygon: triangle))

        // Below the triangle — outside
        XCTAssertFalse(MeshClipper.isPointInPolygon(SIMD2<Float>(0.5, 0.05), polygon: triangle))
    }

    func testPointInPolygon_emptyPolygon() {
        XCTAssertFalse(MeshClipper.isPointInPolygon(SIMD2<Float>(0.5, 0.5), polygon: []))
    }

    // MARK: - Sutherland-Hodgman Clipping

    func testSutherlandHodgmanClip_triangleInsideSquare() {
        let subject: [SIMD2<Float>] = [
            SIMD2<Float>(0.4, 0.4),
            SIMD2<Float>(0.6, 0.4),
            SIMD2<Float>(0.5, 0.6),
        ]

        let clip: [SIMD2<Float>] = [
            SIMD2<Float>(0.2, 0.2),
            SIMD2<Float>(0.8, 0.2),
            SIMD2<Float>(0.8, 0.8),
            SIMD2<Float>(0.2, 0.8),
        ]

        let result = MeshClipper.sutherlandHodgmanClip(subject: subject, clip: clip)
        // Triangle is fully inside — should be unchanged (3 vertices)
        XCTAssertEqual(result.count, 3)
    }

    func testSutherlandHodgmanClip_triangleOutsideSquare() {
        let subject: [SIMD2<Float>] = [
            SIMD2<Float>(1.0, 1.0),
            SIMD2<Float>(1.5, 1.0),
            SIMD2<Float>(1.25, 1.5),
        ]

        let clip: [SIMD2<Float>] = [
            SIMD2<Float>(0.0, 0.0),
            SIMD2<Float>(0.5, 0.0),
            SIMD2<Float>(0.5, 0.5),
            SIMD2<Float>(0.0, 0.5),
        ]

        let result = MeshClipper.sutherlandHodgmanClip(subject: subject, clip: clip)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Barycentric Coordinates

    func testBarycentricCoordinates_centroid() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(1, 0)
        let c = SIMD2<Float>(0.5, 1)
        let centroid = SIMD2<Float>(0.5, 1.0 / 3.0)

        let (u, v, w) = MeshClipper.barycentricCoordinates(point: centroid, a: a, b: b, c: c)

        XCTAssertEqual(u, 1.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(v, 1.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(w, 1.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(u + v + w, 1.0, accuracy: 1e-5)
    }

    func testBarycentricCoordinates_vertex() {
        let a = SIMD2<Float>(0, 0)
        let b = SIMD2<Float>(1, 0)
        let c = SIMD2<Float>(0, 1)

        let (u, v, w) = MeshClipper.barycentricCoordinates(point: a, a: a, b: b, c: c)
        XCTAssertEqual(u, 1.0, accuracy: 0.01)
        XCTAssertEqual(v, 0.0, accuracy: 0.01)
        XCTAssertEqual(w, 0.0, accuracy: 0.01)
    }
}

import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class ContourSimplifierTests: XCTestCase {

    // MARK: - Open Douglas-Peucker

    func test_openDouglasPeucker_keepsCornersDropsColinearInteriors() {
        let line: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 0),
            CGPoint(x: 2, y: 0),
            CGPoint(x: 3, y: 0),
            CGPoint(x: 10, y: 0),
        ]
        let simplified = ContourSimplifier.douglasPeuckerOpen(line, epsilon: 0.5)
        XCTAssertEqual(simplified.count, 2)
        XCTAssertEqual(simplified.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(simplified.last, CGPoint(x: 10, y: 0))
    }

    func test_openDouglasPeucker_keepsHighCurvaturePoint() {
        let zig: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 5, y: 10),   // sharp peak — must be kept
            CGPoint(x: 10, y: 0),
        ]
        let simplified = ContourSimplifier.douglasPeuckerOpen(zig, epsilon: 1.0)
        XCTAssertEqual(simplified.count, 3)
        XCTAssertEqual(simplified[1].y, 10)
    }

    // MARK: - Closed Douglas-Peucker

    func test_closedDouglasPeucker_preservesSquareCorners() {
        // Dense square (20 points per side, 80 total) — simplification must
        // collapse back to ~4 corners.
        var square: [CGPoint] = []
        let steps = 20
        for i in 0..<steps { square.append(CGPoint(x: CGFloat(i) / CGFloat(steps) * 100, y: 0)) }
        for i in 0..<steps { square.append(CGPoint(x: 100, y: CGFloat(i) / CGFloat(steps) * 100)) }
        for i in 0..<steps { square.append(CGPoint(x: 100 - CGFloat(i) / CGFloat(steps) * 100, y: 100)) }
        for i in 0..<steps { square.append(CGPoint(x: 0, y: 100 - CGFloat(i) / CGFloat(steps) * 100)) }

        let simplified = ContourSimplifier.douglasPeuckerClosed(square, epsilon: 1.0)
        XCTAssertEqual(simplified.count, 4, "Square should collapse to 4 corners, got \(simplified.count)")
    }

    // MARK: - Short-Edge Filter

    func test_dropShortEdges_collapsesJitter() {
        let jittery: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.5, y: 0),  // too close — dropped
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10),
        ]
        let filtered = ContourSimplifier.dropShortEdges(jittery, minEdge: 2.0)
        XCTAssertEqual(filtered.count, 4)
    }

    func test_dropShortEdges_preservesClosure() {
        let polygon: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10),
            CGPoint(x: 0.5, y: 0.5), // collapses into first
        ]
        let filtered = ContourSimplifier.dropShortEdges(polygon, minEdge: 2.0)
        XCTAssertEqual(filtered.count, 4, "Tail close to head should be dropped")
    }

    // MARK: - End-to-End simplify()

    func test_simplify_capsAtMaxVertices() {
        // Build a noisy 400-point circle.
        let noisy: [CGPoint] = (0..<400).map { i in
            let t = Double(i) / 400.0 * 2 * .pi
            let r = 50 + Double.random(in: -0.3...0.3)
            return CGPoint(x: 100 + r * cos(t), y: 100 + r * sin(t))
        }
        let simplified = ContourSimplifier.simplify(noisy, maxVertices: 40)
        XCTAssertLessThanOrEqual(simplified.count, 40)
        XCTAssertGreaterThanOrEqual(simplified.count, 8, "Shouldn't collapse to nothing")
    }

    func test_simplify_passesThroughTinyPolygons() {
        let triangle: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 5, y: 10),
        ]
        let simplified = ContourSimplifier.simplify(triangle)
        XCTAssertEqual(simplified.count, 3)
    }
}

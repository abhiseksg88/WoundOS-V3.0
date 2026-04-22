import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class SegmentationResultTests: XCTestCase {

    func testIsUsable_acceptedResult() {
        let result = SegmentationResult(
            polygonImageSpace: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 300, y: 100),
                CGPoint(x: 300, y: 300),
            ],
            imageSize: CGSize(width: 1920, height: 1440),
            confidence: 0.9,
            modelIdentifier: "sam2.server.v1",
            qualityResult: .accept
        )
        XCTAssertTrue(result.isUsable)
    }

    func testIsUsable_rejectedResult() {
        let result = SegmentationResult(
            polygonImageSpace: [],
            imageSize: CGSize(width: 1920, height: 1440),
            confidence: 0.3,
            modelIdentifier: "sam2.server.v1",
            qualityResult: .reject(reason: .confidenceTooLow, detail: "0.3 < 0.5")
        )
        XCTAssertFalse(result.isUsable)
    }

    func testRejectedFactory() {
        let result = SegmentationResult.rejected(
            reason: .degeneratePolygon,
            detail: "Segmentation service unavailable",
            modelIdentifier: "sam2.server.v1",
            imageSize: CGSize(width: 1920, height: 1440)
        )
        XCTAssertFalse(result.isUsable)
        XCTAssertTrue(result.polygonImageSpace.isEmpty)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertEqual(result.connectedComponents, 0)
        XCTAssertEqual(result.qualityResult.rejectionReason, .degeneratePolygon)
    }

    func testDefaultValues() {
        let result = SegmentationResult(
            polygonImageSpace: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)],
            imageSize: CGSize(width: 100, height: 100),
            confidence: 0.8,
            modelIdentifier: "test"
        )
        // Defaults
        XCTAssertEqual(result.connectedComponents, 1)
        XCTAssertEqual(result.qualityResult, .accept)
        XCTAssertEqual(result.inferenceLatencyMs, 0)
    }
}

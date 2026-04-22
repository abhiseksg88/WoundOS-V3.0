import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class SegmentationTelemetryTests: XCTestCase {

    func testTelemetryRecordFromAcceptedResult() {
        let polygon = [
            CGPoint(x: 500, y: 500),
            CGPoint(x: 1500, y: 500),
            CGPoint(x: 1500, y: 1500),
            CGPoint(x: 500, y: 1500),
        ]
        let result = SegmentationResult(
            polygonImageSpace: polygon,
            imageSize: CGSize(width: 4032, height: 3024),
            confidence: 0.85,
            modelIdentifier: "sam2.server.v1",
            connectedComponents: 1,
            qualityResult: .accept,
            inferenceLatencyMs: 450
        )

        let record = SegmentationTelemetryRecord.from(
            result: result,
            onDeviceFlagState: false,
            captureUUID: "test-uuid"
        )

        XCTAssertEqual(record.captureUUID, "test-uuid")
        XCTAssertEqual(record.segmenterIdentifier, "sam2.server.v1")
        XCTAssertEqual(record.inferenceLatencyMs, 450)
        XCTAssertEqual(record.rawConfidence, 0.85)
        XCTAssertEqual(record.rawComponentCount, 1)
        XCTAssertEqual(record.qualityResult, "accept")
        XCTAssertNil(record.qualityDetail)
        XCTAssertFalse(record.onDeviceFlagState)
        XCTAssertTrue(record.rawCoveragePct > 0)
        XCTAssertTrue(record.rawAspectRatio > 0)
    }

    func testTelemetryRecordFromRejectedResult() {
        let result = SegmentationResult.rejected(
            reason: .confidenceTooLow,
            detail: "0.3 < 0.5",
            modelIdentifier: "sam2.server.v1",
            imageSize: CGSize(width: 4032, height: 3024)
        )

        let record = SegmentationTelemetryRecord.from(
            result: result,
            onDeviceFlagState: true
        )

        XCTAssertEqual(record.qualityResult, "confidenceTooLow")
        XCTAssertEqual(record.qualityDetail, "0.3 < 0.5")
        XCTAssertTrue(record.onDeviceFlagState)
        XCTAssertEqual(record.rawConfidence, 0)
    }
}

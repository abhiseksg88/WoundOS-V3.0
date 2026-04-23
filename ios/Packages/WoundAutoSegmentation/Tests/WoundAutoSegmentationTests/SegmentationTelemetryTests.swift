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

    // MARK: - isCanaryRecord Tests

    func testIsCanaryRecord_defaultsFalse() {
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
            onDeviceFlagState: false
        )
        XCTAssertFalse(record.isCanaryRecord)
    }

    func testIsCanaryRecord_explicitTrue() {
        let record = SegmentationTelemetryRecord(
            segmenterIdentifier: "canary.coreml",
            inferenceLatencyMs: 120,
            rawConfidence: 0.98,
            rawCoveragePct: 0,
            rawAspectRatio: 0,
            rawComponentCount: 0,
            qualityResult: "canary_passed",
            onDeviceFlagState: true,
            canaryIoU: 0.98,
            canaryPassed: true,
            chainedSegmenterUsed: true,
            isCanaryRecord: true
        )
        XCTAssertTrue(record.isCanaryRecord)
        XCTAssertEqual(record.segmenterIdentifier, "canary.coreml")
        XCTAssertEqual(record.canaryPassed, true)
    }

    func testIsCanaryRecord_fromFactory_defaultsFalse() {
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
            modelIdentifier: "test",
            connectedComponents: 1,
            qualityResult: .accept,
            inferenceLatencyMs: 100
        )

        let record = SegmentationTelemetryRecord.from(
            result: result,
            onDeviceFlagState: true,
            chainedSegmenterUsed: true
        )
        XCTAssertFalse(record.isCanaryRecord)
    }

    func testIsCanaryRecord_fromFactory_explicitTrue() {
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
            modelIdentifier: "canary.coreml",
            connectedComponents: 1,
            qualityResult: .accept,
            inferenceLatencyMs: 100
        )

        let record = SegmentationTelemetryRecord.from(
            result: result,
            onDeviceFlagState: true,
            canaryIoU: 0.97,
            canaryPassed: true,
            chainedSegmenterUsed: true,
            isCanaryRecord: true
        )
        XCTAssertTrue(record.isCanaryRecord)
    }

    func testCanaryRecordCodable_roundTrip() throws {
        let record = SegmentationTelemetryRecord(
            segmenterIdentifier: "canary.coreml",
            inferenceLatencyMs: 150,
            rawConfidence: 0.96,
            rawCoveragePct: 0,
            rawAspectRatio: 0,
            rawComponentCount: 0,
            qualityResult: "canary_passed",
            qualityDetail: "iou=0.9600, expected=1024, actual=990",
            onDeviceFlagState: true,
            canaryIoU: 0.96,
            canaryPassed: true,
            chainedSegmenterUsed: true,
            isCanaryRecord: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SegmentationTelemetryRecord.self, from: data)

        XCTAssertTrue(decoded.isCanaryRecord)
        XCTAssertEqual(decoded.canaryIoU, 0.96)
        XCTAssertEqual(decoded.canaryPassed, true)
        XCTAssertEqual(decoded.segmenterIdentifier, "canary.coreml")
        XCTAssertEqual(decoded.qualityResult, "canary_passed")
    }
}

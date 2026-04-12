import XCTest
@testable import WoundCore

final class AgreementMetricsTests: XCTestCase {

    // MARK: - Flagging Thresholds

    func testNotFlagged_goodAgreement() {
        let metrics = AgreementMetrics(
            iou: 0.92,
            diceCoefficient: 0.96,
            areaDeltaPercent: 5.0,
            depthDeltaMm: 0.5,
            volumeDeltaMl: 0.2,
            centroidDisplacementMm: 3.0,
            samConfidence: 0.90,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertFalse(metrics.isFlagged)
        XCTAssertTrue(metrics.flagReasons.isEmpty)
    }

    func testFlagged_lowIoU() {
        let metrics = AgreementMetrics(
            iou: 0.55,
            diceCoefficient: 0.71,
            areaDeltaPercent: 10.0,
            depthDeltaMm: 0.3,
            volumeDeltaMl: 0.1,
            centroidDisplacementMm: 5.0,
            samConfidence: 0.85,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertTrue(metrics.isFlagged)
        XCTAssertTrue(metrics.flagReasons.contains(where: { $0.contains("IoU") }))
    }

    func testFlagged_highAreaDelta() {
        let metrics = AgreementMetrics(
            iou: 0.80,
            diceCoefficient: 0.88,
            areaDeltaPercent: 25.0,
            depthDeltaMm: 0.5,
            volumeDeltaMl: 0.5,
            centroidDisplacementMm: 5.0,
            samConfidence: 0.85,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertTrue(metrics.isFlagged)
        XCTAssertTrue(metrics.flagReasons.contains(where: { $0.contains("Area") }))
    }

    func testFlagged_highDepthDelta() {
        let metrics = AgreementMetrics(
            iou: 0.85,
            diceCoefficient: 0.92,
            areaDeltaPercent: 8.0,
            depthDeltaMm: 3.5,
            volumeDeltaMl: 1.0,
            centroidDisplacementMm: 5.0,
            samConfidence: 0.90,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertTrue(metrics.isFlagged)
        XCTAssertTrue(metrics.flagReasons.contains(where: { $0.contains("Depth") }))
    }

    func testFlagged_largeCentroidDisplacement() {
        let metrics = AgreementMetrics(
            iou: 0.75,
            diceCoefficient: 0.85,
            areaDeltaPercent: 10.0,
            depthDeltaMm: 1.0,
            volumeDeltaMl: 0.5,
            centroidDisplacementMm: 25.0,
            samConfidence: 0.80,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertTrue(metrics.isFlagged)
        XCTAssertTrue(metrics.flagReasons.contains(where: { $0.contains("centers") }))
    }

    func testFlagged_multipleReasons() {
        let metrics = AgreementMetrics(
            iou: 0.40,
            diceCoefficient: 0.57,
            areaDeltaPercent: 35.0,
            depthDeltaMm: 4.0,
            volumeDeltaMl: 2.0,
            centroidDisplacementMm: 30.0,
            samConfidence: 0.50,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertTrue(metrics.isFlagged)
        XCTAssertEqual(metrics.flagReasons.count, 4)
    }

    // MARK: - Boundary Values

    func testBorderline_iou() {
        let justAbove = AgreementMetrics(
            iou: 0.70,
            diceCoefficient: 0.82,
            areaDeltaPercent: 15.0,
            depthDeltaMm: 1.5,
            volumeDeltaMl: 0.5,
            centroidDisplacementMm: 10.0,
            samConfidence: 0.85,
            samModelVersion: "sam2-v1.0"
        )
        // IoU == 0.70 is NOT < 0.70, so not flagged by IoU threshold
        XCTAssertFalse(justAbove.flagReasons.contains(where: { $0.contains("IoU") }))

        let justBelow = AgreementMetrics(
            iou: 0.699,
            diceCoefficient: 0.82,
            areaDeltaPercent: 15.0,
            depthDeltaMm: 1.5,
            volumeDeltaMl: 0.5,
            centroidDisplacementMm: 10.0,
            samConfidence: 0.85,
            samModelVersion: "sam2-v1.0"
        )
        XCTAssertTrue(justBelow.flagReasons.contains(where: { $0.contains("IoU") }))
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = AgreementMetrics(
            iou: 0.87,
            diceCoefficient: 0.93,
            areaDeltaPercent: 6.2,
            depthDeltaMm: 0.8,
            volumeDeltaMl: 0.3,
            centroidDisplacementMm: 4.5,
            samConfidence: 0.91,
            samModelVersion: "sam2-v1.2"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgreementMetrics.self, from: data)

        XCTAssertEqual(decoded.iou, original.iou, accuracy: 0.001)
        XCTAssertEqual(decoded.isFlagged, original.isFlagged)
    }
}

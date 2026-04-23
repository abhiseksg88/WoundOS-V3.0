import XCTest
@testable import WoundAutoSegmentation

final class CoreMLCanaryValidatorTests: XCTestCase {

    // MARK: - IoU Computation Tests

    func testIoU_identicalMasks_returns1() {
        let mask: [UInt8] = [0, 255, 255, 0, 255, 0, 0, 255, 255]
        let iou = CoreMLCanaryValidator.computeIoU(predicted: mask, reference: mask)
        XCTAssertEqual(iou, 1.0, accuracy: 0.001)
    }

    func testIoU_disjointMasks_returns0() {
        let predicted: [UInt8] = [255, 255, 0, 0]
        let reference: [UInt8] = [0, 0, 255, 255]
        let iou = CoreMLCanaryValidator.computeIoU(predicted: predicted, reference: reference)
        XCTAssertEqual(iou, 0.0, accuracy: 0.001)
    }

    func testIoU_partialOverlap() {
        // Predicted: [1, 1, 0, 0]
        // Reference: [0, 1, 1, 0]
        // Intersection: [0, 1, 0, 0] = 1 pixel
        // Union:        [1, 1, 1, 0] = 3 pixels
        // IoU = 1/3 ≈ 0.333
        let predicted: [UInt8] = [255, 255, 0, 0]
        let reference: [UInt8] = [0, 255, 255, 0]
        let iou = CoreMLCanaryValidator.computeIoU(predicted: predicted, reference: reference)
        XCTAssertEqual(iou, 1.0 / 3.0, accuracy: 0.001)
    }

    func testIoU_emptyMasks_returns0() {
        let mask: [UInt8] = [0, 0, 0, 0]
        let iou = CoreMLCanaryValidator.computeIoU(predicted: mask, reference: mask)
        XCTAssertEqual(iou, 0.0, accuracy: 0.001)
    }

    func testIoU_emptyArrays_returns0() {
        let iou = CoreMLCanaryValidator.computeIoU(predicted: [], reference: [])
        XCTAssertEqual(iou, 0.0)
    }

    func testIoU_mismatchedLengths_returns0() {
        let predicted: [UInt8] = [255, 0]
        let reference: [UInt8] = [255, 0, 255]
        let iou = CoreMLCanaryValidator.computeIoU(predicted: predicted, reference: reference)
        XCTAssertEqual(iou, 0.0)
    }

    func testIoU_allForeground_returns1() {
        let mask: [UInt8] = [255, 255, 255, 255]
        let iou = CoreMLCanaryValidator.computeIoU(predicted: mask, reference: mask)
        XCTAssertEqual(iou, 1.0, accuracy: 0.001)
    }

    // MARK: - Constants

    func testIoUThreshold() {
        XCTAssertEqual(CoreMLCanaryValidator.iouThreshold, 0.95)
    }

    func testExpectedPositivePixels() {
        XCTAssertEqual(CoreMLCanaryValidator.expectedPositivePixels, 13_132)
    }

    func testMaskSize() {
        XCTAssertEqual(CoreMLCanaryValidator.maskSize, 512)
    }
}

import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class CoreMLBoundarySegmenterTests: XCTestCase {

    func testModelIdentifier() {
        XCTAssertEqual(
            CoreMLBoundarySegmenter.modelIdentifier,
            "boundaryseg.coreml.v1"
        )
    }

    func testInit_throwsWhenModelNotBundled() {
        // BoundarySeg.mlpackage is not bundled in test target → init should throw
        XCTAssertThrowsError(try CoreMLBoundarySegmenter()) { error in
            guard let segError = error as? SegmentationError else {
                XCTFail("Expected SegmentationError, got \(error)")
                return
            }
            XCTAssertEqual(
                segError.localizedDescription,
                SegmentationError.modelLoadFailed.localizedDescription
            )
        }
    }

    func testInit_withCustomThresholds_throwsWhenModelNotBundled() {
        let thresholds = MaskQualityThresholds(minConfidence: 0.8)
        XCTAssertThrowsError(try CoreMLBoundarySegmenter(qualityThresholds: thresholds)) { error in
            XCTAssertTrue(error is SegmentationError)
        }
    }
}

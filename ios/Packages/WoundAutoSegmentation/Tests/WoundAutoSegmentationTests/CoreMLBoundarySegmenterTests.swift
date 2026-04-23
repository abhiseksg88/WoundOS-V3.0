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

    func testInit_succeeds_whenModelBundled() {
        // BoundarySeg.mlpackage is bundled → init should succeed
        XCTAssertNoThrow(try CoreMLBoundarySegmenter())
    }

    func testInit_withCustomThresholds_succeeds() {
        let thresholds = MaskQualityThresholds(minConfidence: 0.8)
        XCTAssertNoThrow(try CoreMLBoundarySegmenter(qualityThresholds: thresholds))
    }
}

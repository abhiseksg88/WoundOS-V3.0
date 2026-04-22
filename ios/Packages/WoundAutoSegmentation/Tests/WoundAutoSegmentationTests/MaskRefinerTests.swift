import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class MaskRefinerTests: XCTestCase {

    func testIdentityRefiner_returnsInputUnchanged() async throws {
        let refiner = IdentityMaskRefiner()

        let input = SegmentationResult(
            polygonImageSpace: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 300, y: 100),
                CGPoint(x: 300, y: 300),
                CGPoint(x: 100, y: 300),
            ],
            imageSize: CGSize(width: 1920, height: 1440),
            confidence: 0.92,
            modelIdentifier: "sam2.server.v1",
            connectedComponents: 1,
            qualityResult: .accept,
            inferenceLatencyMs: 450
        )

        let context = MaskRefinementContext(
            capturedAt: Date(),
            deviceModel: "iPhone14,5",
            captureDistanceMeters: 0.25,
            lidarConfidencePercent: 0.85
        )

        let output = try await refiner.refine(mask: input, context: context)

        // Output must be identical to input
        XCTAssertEqual(output.polygonImageSpace, input.polygonImageSpace)
        XCTAssertEqual(output.imageSize, input.imageSize)
        XCTAssertEqual(output.confidence, input.confidence)
        XCTAssertEqual(output.modelIdentifier, input.modelIdentifier)
        XCTAssertEqual(output.connectedComponents, input.connectedComponents)
        XCTAssertEqual(output.qualityResult, input.qualityResult)
        XCTAssertEqual(output.inferenceLatencyMs, input.inferenceLatencyMs)
    }

    func testIdentityRefiner_properties() {
        let refiner = IdentityMaskRefiner()
        XCTAssertEqual(refiner.identifier, "identity.v1")
        XCTAssertFalse(refiner.requiresNetwork)
    }
}

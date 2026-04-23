import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

// MARK: - Mock Segmenter

final class MockSegmenter: WoundSegmenter {
    var handler: ((CGImage, CGPoint) async throws -> SegmentationResult)?
    var callCount = 0

    func segment(image: CGImage, tapPoint: CGPoint) async throws -> SegmentationResult {
        callCount += 1
        guard let handler else {
            throw SegmentationError.predictionFailed
        }
        return try await handler(image, tapPoint)
    }
}

// MARK: - Mock Canary Validator

/// Minimal canary validator substitute for testing ChainedSegmenter logic.
/// We can't create a real CoreMLCanaryValidator without a real CoreMLBoundarySegmenter,
/// so we test the ChainedSegmenter with canaryValidator = nil (canary skipped).

// MARK: - Tests

final class ChainedSegmenterTests: XCTestCase {

    let testImageSize = CGSize(width: 512, height: 512)
    let testTapPoint = CGPoint(x: 256, y: 256)

    /// Create a minimal 1×1 CGImage for testing.
    private func makeTestImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1, height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func makeAcceptedResult(modelId: String) -> SegmentationResult {
        SegmentationResult(
            polygonImageSpace: [
                CGPoint(x: 100, y: 100),
                CGPoint(x: 300, y: 100),
                CGPoint(x: 300, y: 300),
                CGPoint(x: 100, y: 300),
            ],
            imageSize: testImageSize,
            confidence: 0.9,
            modelIdentifier: modelId,
            connectedComponents: 1,
            qualityResult: .accept,
            inferenceLatencyMs: 50
        )
    }

    // MARK: - Fallback when primary is nil

    func testFallsBackToServer_whenPrimaryIsNil() async throws {
        let fallback = MockSegmenter()
        let expectedResult = makeAcceptedResult(modelId: "sam2.server.v1")
        fallback.handler = { _, _ in expectedResult }

        let chained = ChainedSegmenter(
            primary: nil,
            fallback: fallback,
            canaryValidator: nil
        )

        let image = makeTestImage()
        let result = try await chained.segment(image: image, tapPoint: testTapPoint)

        XCTAssertEqual(result.modelIdentifier, "sam2.server.v1")
        XCTAssertEqual(fallback.callCount, 1)
        XCTAssertEqual(chained.lastFallbackReason, .coremlLoadFailed)
    }

    // MARK: - Primary succeeds (no canary validator)

    func testUsesPrimary_whenCanarySkipped() async throws {
        let primary = MockSegmenter()
        let fallback = MockSegmenter()

        let primaryResult = makeAcceptedResult(modelId: "boundaryseg.coreml.v1")
        primary.handler = { _, _ in primaryResult }
        fallback.handler = { _, _ in self.makeAcceptedResult(modelId: "sam2.server.v1") }

        let chained = ChainedSegmenter(
            primary: primary,
            fallback: fallback,
            canaryValidator: nil // no canary → skipped, assume pass
        )

        let image = makeTestImage()
        let result = try await chained.segment(image: image, tapPoint: testTapPoint)

        XCTAssertEqual(result.modelIdentifier, "boundaryseg.coreml.v1")
        XCTAssertEqual(primary.callCount, 1)
        XCTAssertEqual(fallback.callCount, 0)
        XCTAssertNil(chained.lastFallbackReason)
    }

    // MARK: - Primary throws → fallback

    func testFallsBackToServer_whenPrimaryThrows() async throws {
        let primary = MockSegmenter()
        let fallback = MockSegmenter()

        primary.handler = { _, _ in throw SegmentationError.predictionFailed }
        let fallbackResult = makeAcceptedResult(modelId: "sam2.server.v1")
        fallback.handler = { _, _ in fallbackResult }

        let chained = ChainedSegmenter(
            primary: primary,
            fallback: fallback,
            canaryValidator: nil
        )

        let image = makeTestImage()
        let result = try await chained.segment(image: image, tapPoint: testTapPoint)

        XCTAssertEqual(result.modelIdentifier, "sam2.server.v1")
        XCTAssertEqual(primary.callCount, 1)
        XCTAssertEqual(fallback.callCount, 1)
        XCTAssertEqual(chained.lastFallbackReason, .coremlInferenceFailed)
    }

    // MARK: - Both throw → error propagates

    func testThrows_whenBothSegmentersFail() async {
        let primary = MockSegmenter()
        let fallback = MockSegmenter()

        primary.handler = { _, _ in throw SegmentationError.predictionFailed }
        fallback.handler = { _, _ in throw SegmentationError.serviceUnavailable(underlying: nil) }

        let chained = ChainedSegmenter(
            primary: primary,
            fallback: fallback,
            canaryValidator: nil
        )

        let image = makeTestImage()
        do {
            _ = try await chained.segment(image: image, tapPoint: testTapPoint)
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected — fallback threw
            XCTAssertTrue(error is SegmentationError)
        }
    }

    // MARK: - Multiple calls use same primary

    func testMultipleCalls_usePrimary() async throws {
        let primary = MockSegmenter()
        let fallback = MockSegmenter()

        let primaryResult = makeAcceptedResult(modelId: "boundaryseg.coreml.v1")
        primary.handler = { _, _ in primaryResult }

        let chained = ChainedSegmenter(
            primary: primary,
            fallback: fallback,
            canaryValidator: nil
        )

        let image = makeTestImage()
        _ = try await chained.segment(image: image, tapPoint: testTapPoint)
        _ = try await chained.segment(image: image, tapPoint: testTapPoint)
        _ = try await chained.segment(image: image, tapPoint: testTapPoint)

        XCTAssertEqual(primary.callCount, 3)
        XCTAssertEqual(fallback.callCount, 0)
    }

    // MARK: - Fallback reason tracking

    func testFallbackReason_clearsAfterPrimarySuccess() async throws {
        let primary = MockSegmenter()
        let fallback = MockSegmenter()

        var callIndex = 0
        let primaryResult = makeAcceptedResult(modelId: "boundaryseg.coreml.v1")
        let fallbackResult = makeAcceptedResult(modelId: "sam2.server.v1")

        primary.handler = { _, _ in
            callIndex += 1
            if callIndex == 1 {
                throw SegmentationError.predictionFailed
            }
            return primaryResult
        }
        fallback.handler = { _, _ in fallbackResult }

        let chained = ChainedSegmenter(
            primary: primary,
            fallback: fallback,
            canaryValidator: nil
        )

        let image = makeTestImage()

        // First call — primary fails, fallback used
        let result1 = try await chained.segment(image: image, tapPoint: testTapPoint)
        XCTAssertEqual(result1.modelIdentifier, "sam2.server.v1")
        XCTAssertEqual(chained.lastFallbackReason, .coremlInferenceFailed)

        // Second call — primary succeeds
        let result2 = try await chained.segment(image: image, tapPoint: testTapPoint)
        XCTAssertEqual(result2.modelIdentifier, "boundaryseg.coreml.v1")
        XCTAssertNil(chained.lastFallbackReason)
    }
}

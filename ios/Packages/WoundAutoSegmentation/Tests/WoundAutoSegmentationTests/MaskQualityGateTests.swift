import XCTest
import CoreGraphics
@testable import WoundAutoSegmentation

final class MaskQualityGateTests: XCTestCase {

    let frameSize = CGSize(width: 4032, height: 3024)

    // MARK: - Degenerate Polygon

    func testEmptyPolygon_rejectsDegeneratePolygon() {
        let result = MaskQualityGate.evaluate(
            polygon: [],
            imageSize: frameSize,
            confidence: 0.9,
            connectedComponents: 1
        )
        XCTAssertEqual(result, .reject(
            reason: .degeneratePolygon,
            detail: "Polygon has 0 vertices (minimum 3)"
        ))
    }

    func testTwoPointPolygon_rejectsDegeneratePolygon() {
        let polygon = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)]
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.9,
            connectedComponents: 1
        )
        XCTAssertEqual(result, .reject(
            reason: .degeneratePolygon,
            detail: "Polygon has 2 vertices (minimum 3)"
        ))
    }

    // MARK: - Full-Frame Polygon

    func testFullFramePolygon_rejectsCoverageTooLargeOrFrameEdge() {
        // Polygon covering 100% of the frame
        let polygon = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 4032, y: 0),
            CGPoint(x: 4032, y: 3024),
            CGPoint(x: 0, y: 3024),
        ]
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.9,
            connectedComponents: 1
        )
        // Should reject — either coverageTooLarge or frameEdgeContact
        guard case .reject(let reason, _) = result else {
            XCTFail("Expected rejection, got accept")
            return
        }
        XCTAssertTrue(
            reason == .coverageTooLarge || reason == .frameEdgeContact,
            "Expected coverageTooLarge or frameEdgeContact, got \(reason)"
        )
    }

    // MARK: - Tiny Polygon (< 0.1% coverage)

    func testTinyPolygon_rejectsCoverageTooSmall() {
        // 50×50 pixel polygon in 4032×3024 frame = ~0.02% coverage
        let polygon = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 150, y: 100),
            CGPoint(x: 150, y: 150),
            CGPoint(x: 100, y: 150),
        ]
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.9,
            connectedComponents: 1
        )
        guard case .reject(let reason, _) = result else {
            XCTFail("Expected rejection, got accept")
            return
        }
        XCTAssertEqual(reason, .coverageTooSmall)
    }

    // MARK: - Clean 10% Wound

    func testCleanWoundPolygon_accepts() {
        // ~10% coverage wound-like polygon, aspect ratio ~0.8
        // Frame = 4032×3024, 10% area = 1,217,664 pixels
        // Roughly 1200×1015 polygon
        let cx: CGFloat = 2016
        let cy: CGFloat = 1512
        let w: CGFloat = 600
        let h: CGFloat = 480
        let polygon = [
            CGPoint(x: cx - w, y: cy - h),
            CGPoint(x: cx + w, y: cy - h),
            CGPoint(x: cx + w, y: cy + h),
            CGPoint(x: cx - w, y: cy + h),
        ]
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.85,
            connectedComponents: 1
        )
        XCTAssertEqual(result, .accept)
    }

    // MARK: - Low Confidence

    func testLowConfidence_rejectsConfidenceTooLow() {
        let polygon = makeSquarePolygon(center: CGPoint(x: 2016, y: 1512), size: 500)
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.3,
            connectedComponents: 1
        )
        guard case .reject(let reason, _) = result else {
            XCTFail("Expected rejection, got accept")
            return
        }
        XCTAssertEqual(reason, .confidenceTooLow)
    }

    // MARK: - Stripe Polygon (Invalid Aspect Ratio)

    func testStripePolygon_rejectsAspectRatioInvalid() {
        // 3000×50 stripe — 1.23% coverage (passes min), aspect ratio = 50/3000 = 0.017 (below 0.15)
        let polygon = [
            CGPoint(x: 500, y: 1500),
            CGPoint(x: 3500, y: 1500),
            CGPoint(x: 3500, y: 1550),
            CGPoint(x: 500, y: 1550),
        ]
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.9,
            connectedComponents: 1
        )
        guard case .reject(let reason, _) = result else {
            XCTFail("Expected rejection, got accept")
            return
        }
        XCTAssertEqual(reason, .aspectRatioInvalid)
    }

    // MARK: - Disconnected Components

    func testDisconnectedComponents_rejectsMultipleRegions() {
        let polygon = makeSquarePolygon(center: CGPoint(x: 2016, y: 1512), size: 500)
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.9,
            connectedComponents: 2
        )
        guard case .reject(let reason, _) = result else {
            XCTFail("Expected rejection, got accept")
            return
        }
        XCTAssertEqual(reason, .disconnectedComponents)
    }

    // MARK: - Threshold Edge Cases

    func testExactMinCoverage_accepts() {
        // Create a polygon just above 1% coverage
        // 1% of 4032×3024 = 121,766.88 sq pixels
        // Square side = sqrt(121767) ≈ 349, use 350 to ensure > 1%
        let polygon = makeSquarePolygon(center: CGPoint(x: 2016, y: 1512), size: 350)
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.85,
            connectedComponents: 1
        )
        XCTAssertEqual(result, .accept)
    }

    func testExactMinConfidence_accepts() {
        let polygon = makeSquarePolygon(center: CGPoint(x: 2016, y: 1512), size: 500)
        let result = MaskQualityGate.evaluate(
            polygon: polygon,
            imageSize: frameSize,
            confidence: 0.5,
            connectedComponents: 1
        )
        XCTAssertEqual(result, .accept)
    }

    // MARK: - User Messages

    func testUserMessages_allReasonsHaveMessages() {
        let reasons: [MaskRejectionReason] = [
            .coverageTooSmall, .coverageTooLarge, .frameEdgeContact,
            .aspectRatioInvalid, .disconnectedComponents,
            .confidenceTooLow, .degeneratePolygon,
        ]
        for reason in reasons {
            let msg = MaskQualityGate.userMessage(for: reason)
            XCTAssertFalse(msg.isEmpty, "No message for \(reason)")
        }
    }

    // MARK: - Helpers

    private func makeSquarePolygon(center: CGPoint, size: CGFloat) -> [CGPoint] {
        let half = size / 2
        return [
            CGPoint(x: center.x - half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y - half),
            CGPoint(x: center.x + half, y: center.y + half),
            CGPoint(x: center.x - half, y: center.y + half),
        ]
    }
}

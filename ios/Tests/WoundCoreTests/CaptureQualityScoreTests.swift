import XCTest
@testable import WoundCore

final class CaptureQualityScoreTests: XCTestCase {

    // MARK: - Tier Computation

    func testExcellentTier() {
        let score = CaptureQualityScore(
            trackingStableSeconds: 2.0,
            captureDistanceM: 0.20,
            meshVertexCount: 800,
            meanDepthConfidence: 1.95,
            meshHitRate: 1.0,
            angularVelocityRadPerSec: 0.01
        )
        XCTAssertEqual(score.tier, .excellent)
    }

    func testGoodTier_oneSignalDown() {
        // distance just slightly out of optimal range
        let score = CaptureQualityScore(
            trackingStableSeconds: 2.0,
            captureDistanceM: 0.32,
            meshVertexCount: 800,
            meanDepthConfidence: 1.95,
            meshHitRate: 1.0,
            angularVelocityRadPerSec: 0.01
        )
        XCTAssertEqual(score.tier, .good)
    }

    func testFairTier_twoSignalsDown() {
        let score = CaptureQualityScore(
            trackingStableSeconds: 2.0,
            captureDistanceM: 0.50,         // out of range
            meshVertexCount: 800,
            meanDepthConfidence: 1.0,       // not high enough
            meshHitRate: 1.0,
            angularVelocityRadPerSec: 0.01
        )
        XCTAssertEqual(score.tier, .fair)
    }

    func testPoorTier_multipleSignalsDown() {
        let score = CaptureQualityScore(
            trackingStableSeconds: 0.5,     // not stable
            captureDistanceM: 0.50,         // too far
            meshVertexCount: 100,           // not dense
            meanDepthConfidence: 0.5,       // low confidence
            meshHitRate: 0.6,               // low hit rate
            angularVelocityRadPerSec: 0.20  // too much motion
        )
        XCTAssertEqual(score.tier, .poor)
    }

    // MARK: - Codable Round Trip

    func testCodableRoundTrip() throws {
        let original = CaptureQualityScore(
            trackingStableSeconds: 1.8,
            captureDistanceM: 0.22,
            meshVertexCount: 654,
            meanDepthConfidence: 1.85,
            meshHitRate: 0.97,
            angularVelocityRadPerSec: 0.03
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CaptureQualityScore.self, from: data)

        XCTAssertEqual(decoded.trackingStableSeconds, original.trackingStableSeconds)
        XCTAssertEqual(decoded.captureDistanceM, original.captureDistanceM)
        XCTAssertEqual(decoded.meshVertexCount, original.meshVertexCount)
        XCTAssertEqual(decoded.meshHitRate, original.meshHitRate)
        XCTAssertEqual(decoded.tier, original.tier)
    }
}

import XCTest
@testable import WoundCapture
import WoundCore

final class CaptureQualityMonitorTests: XCTestCase {

    func testInitialState_isNotReady() {
        let monitor = CaptureQualityMonitor()
        XCTAssertFalse(monitor.currentReadiness.isReady)
        XCTAssertNil(monitor.lastDistance)
        XCTAssertEqual(monitor.lastVertexCount, 0)
        XCTAssertEqual(monitor.lastAngularVelocity, 0)
    }

    func testReset_clearsAllState() {
        let monitor = CaptureQualityMonitor()
        monitor.reset()

        XCTAssertNil(monitor.lastDistance)
        XCTAssertEqual(monitor.lastVertexCount, 0)
        XCTAssertEqual(monitor.lastAngularVelocity, 0)
        XCTAssertEqual(monitor.trackingStableSeconds, 0)
        XCTAssertFalse(monitor.currentReadiness.isReady)
    }

    func testQualityScoreSnapshot_producesValidScore() {
        let monitor = CaptureQualityMonitor()
        let score = monitor.qualityScoreSnapshot(
            meshVertexCount: 1000,
            meanDepthConfidence: 1.8,
            meshHitRate: 0.95
        )
        XCTAssertEqual(score.meshVertexCount, 1000)
        XCTAssertEqual(score.meanDepthConfidence, 1.8, accuracy: 0.001)
        XCTAssertEqual(score.meshHitRate, 0.95, accuracy: 0.001)
        XCTAssertEqual(score.trackingStableSeconds, 0, accuracy: 0.1)
    }

    func testDefaultConfiguration() {
        let config = CaptureQualityMonitor.Configuration.default
        XCTAssertEqual(config.optimalDistance, 0.15...0.30)
        XCTAssertEqual(config.stableThreshold, 1.5)
        XCTAssertEqual(config.minMeshVertices, 500)
        XCTAssertEqual(config.maxAngularVelocity, 0.05, accuracy: 0.001)
    }

    func testCustomConfiguration() {
        let config = CaptureQualityMonitor.Configuration(
            optimalDistance: 0.20...0.35,
            stableThreshold: 2.0,
            minMeshVertices: 1000,
            maxAngularVelocity: 0.03,
            motionWindowSeconds: 1.0
        )
        let monitor = CaptureQualityMonitor(configuration: config)
        // Verify monitor uses custom config by checking score output
        let score = monitor.qualityScoreSnapshot(
            meshVertexCount: 500,
            meanDepthConfidence: 1.5,
            meshHitRate: 0.8
        )
        // Distance is nil (no frames processed), so quality should be poor
        XCTAssertEqual(score.tier, .poor)
    }
}

import XCTest
@testable import WoundCore

final class CaptureBundleTests: XCTestCase {

    func testCaptureBundle_codableRoundTrip() throws {
        let captureData = CaptureData(
            rgbImageData: Data([0xFF, 0xD8]),
            imageWidth: 1920,
            imageHeight: 1440,
            depthMapData: Data(),
            depthWidth: 256,
            depthHeight: 192,
            confidenceMapData: Data(),
            meshVerticesData: Data(),
            meshFacesData: Data(),
            meshNormalsData: Data(),
            vertexCount: 0,
            faceCount: 0,
            cameraIntrinsics: [1500, 0, 0, 0, 1500, 0, 960, 720, 1],
            cameraTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            deviceModel: "TestDevice",
            lidarAvailable: true
        )

        let qualityScore = CaptureQualityScore(
            trackingStableSeconds: 2.5,
            captureDistanceM: 0.25,
            meshVertexCount: 1000,
            meanDepthConfidence: 1.8,
            meshHitRate: 0.95,
            angularVelocityRadPerSec: 0.02
        )

        let bundle = CaptureBundle(
            captureData: captureData,
            captureMode: .singleShot,
            qualityScore: qualityScore,
            confidenceSummary: ConfidenceSummary(
                highFraction: 0.7,
                mediumFraction: 0.2,
                lowFraction: 0.1
            ),
            sessionMetadata: CaptureSessionMetadata(
                deviceModel: "TestDevice",
                osVersion: "17.0",
                appVersion: "5.0.0",
                lidarAvailable: true,
                trackingStableSeconds: 2.5,
                captureDistanceM: 0.25,
                meshAnchorCount: 3,
                sessionDurationSeconds: 15.0
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CaptureBundle.self, from: data)

        XCTAssertEqual(decoded.id, bundle.id)
        XCTAssertEqual(decoded.captureMode, .singleShot)
        XCTAssertEqual(decoded.qualityScore.tier, qualityScore.tier)
        XCTAssertEqual(decoded.confidenceSummary.highFraction, 0.7, accuracy: 0.001)
        XCTAssertEqual(decoded.sessionMetadata.deviceModel, "TestDevice")
        XCTAssertEqual(decoded.captureData.imageWidth, 1920)
    }

    func testCaptureMode_allCases() {
        XCTAssertEqual(CaptureMode.singleShot.rawValue, "singleShot")
        XCTAssertEqual(CaptureMode.scanMode.rawValue, "scanMode")
        XCTAssertEqual(CaptureMode.photoOnly.rawValue, "photoOnly")
    }

    func testConfidenceSummary_overallScore() {
        let summary = ConfidenceSummary(
            highFraction: 0.6,
            mediumFraction: 0.3,
            lowFraction: 0.1
        )
        XCTAssertEqual(summary.overallScore, 0.75, accuracy: 0.001)
    }

    func testConfidenceSummary_fromConfidenceMap() {
        // 10 pixels: 5 high (2), 3 medium (1), 2 low (0)
        let map: [UInt8] = [2, 2, 2, 2, 2, 1, 1, 1, 0, 0]
        let summary = ConfidenceSummary(fromConfidenceMap: map)

        XCTAssertEqual(summary.highFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.mediumFraction, 0.3, accuracy: 0.001)
        XCTAssertEqual(summary.lowFraction, 0.2, accuracy: 0.001)
    }

    func testConfidenceSummary_emptyMap() {
        let summary = ConfidenceSummary(fromConfidenceMap: [])
        XCTAssertEqual(summary.highFraction, 0)
        XCTAssertEqual(summary.mediumFraction, 0)
        XCTAssertEqual(summary.lowFraction, 0)
    }
}

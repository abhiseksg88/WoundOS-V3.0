import XCTest
@testable import WoundCapture
import WoundCore

final class MockCaptureProviderTests: XCTestCase {

    func testSyntheticSnapshot_hasCorrectDimensions() {
        let snapshot = MockCaptureProvider.syntheticSnapshot(sideMeters: 0.04, divisions: 10)

        // 11x11 grid of vertices = 121 vertices
        XCTAssertEqual(snapshot.vertices.count, 121)
        // 10x10 grid of quads, 2 triangles each = 200 faces
        XCTAssertEqual(snapshot.faces.count, 200)
        // One normal per vertex
        XCTAssertEqual(snapshot.normals.count, 121)

        XCTAssertEqual(snapshot.imageWidth, 1920)
        XCTAssertEqual(snapshot.imageHeight, 1440)
        XCTAssertEqual(snapshot.depthWidth, 256)
        XCTAssertEqual(snapshot.depthHeight, 192)
        XCTAssertEqual(snapshot.depthMap.count, 256 * 192)
        XCTAssertEqual(snapshot.confidenceMap.count, 256 * 192)
        XCTAssertFalse(snapshot.rgbImageData.isEmpty)
        XCTAssertEqual(snapshot.deviceModel, "MockDevice")
    }

    func testMockProvider_startSession() throws {
        let mock = MockCaptureProvider()
        XCTAssertFalse(mock.startSessionCalled)
        XCTAssertFalse(mock.isSessionActive)

        try mock.startSession()

        XCTAssertTrue(mock.startSessionCalled)
        XCTAssertTrue(mock.isSessionActive)
    }

    func testMockProvider_pauseSession() throws {
        let mock = MockCaptureProvider()
        try mock.startSession()
        mock.pauseSession()

        XCTAssertTrue(mock.pauseSessionCalled)
        XCTAssertFalse(mock.isSessionActive)
    }

    func testMockProvider_captureSnapshot_returnsStubbed() throws {
        let mock = MockCaptureProvider()
        let snapshot = try mock.captureSnapshot()

        XCTAssertTrue(mock.captureSnapshotCalled)
        XCTAssertEqual(snapshot.vertices.count, 121) // default synthetic
    }

    func testMockProvider_captureSnapshot_throwsStubbedError() {
        let mock = MockCaptureProvider()
        mock.stubbedError = CaptureError.noFrameAvailable

        XCTAssertThrowsError(try mock.captureSnapshot()) { error in
            XCTAssertEqual(error as? CaptureError, .noFrameAvailable)
        }
    }

    func testMockProvider_startSession_throwsStubbedError() {
        let mock = MockCaptureProvider()
        mock.stubbedError = CaptureError.lidarNotAvailable

        XCTAssertThrowsError(try mock.startSession()) { error in
            XCTAssertEqual(error as? CaptureError, .lidarNotAvailable)
        }
    }
}

import XCTest
@testable import CaptureSync

final class ClinicalPlatformClientTests: XCTestCase {

    private var mockSession: URLSession!
    private let testBaseURL = URL(string: "https://test.example.com")!

    override func setUp() {
        super.setUp()
        mockSession = makeMockSession()
        URLProtocolMock.requestHandler = nil
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Verify: Success (200)

    func testVerifySuccess() async throws {
        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/auth/verify"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cpx_test_token")

            let json = """
            {
                "valid": true,
                "user": {
                    "id": "user-123",
                    "name": "Test Nurse",
                    "email": "nurse@test.com",
                    "role": "nurse",
                    "facility_id": "facility-001",
                    "token_label": "iOS integration test token"
                }
            }
            """.data(using: .utf8)!

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let client = ClinicalPlatformClient(session: mockSession)
        let user = try await client.verify(token: "cpx_test_token", baseURL: testBaseURL)

        XCTAssertEqual(user.userId, "user-123")
        XCTAssertEqual(user.name, "Test Nurse")
        XCTAssertEqual(user.email, "nurse@test.com")
        XCTAssertEqual(user.role, "nurse")
        XCTAssertEqual(user.facilityId, "facility-001")
        XCTAssertEqual(user.tokenLabel, "iOS integration test token")
    }

    // MARK: - Verify: Unauthorized (401)

    func testVerifyUnauthorized() async {
        URLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.verify(token: "bad_token", baseURL: testBaseURL)
            XCTFail("Expected unauthorized error")
        } catch let error as ClinicalPlatformError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Verify: Network Error

    func testVerifyNetworkError() async {
        URLProtocolMock.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.verify(token: "token", baseURL: testBaseURL)
            XCTFail("Expected network error")
        } catch let error as ClinicalPlatformError {
            if case .networkError = error {
                XCTAssertTrue(error.isRetryable)
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Verify: Server Error (500)

    func testVerifyServerError() async {
        URLProtocolMock.requestHandler = { request in
            let json = """
            {"error": "Internal Server Error"}
            """.data(using: .utf8)!

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.verify(token: "token", baseURL: testBaseURL)
            XCTFail("Expected server error")
        } catch let error as ClinicalPlatformError {
            if case .serverError(let code, _) = error {
                XCTAssertEqual(code, 500)
                XCTAssertTrue(error.isRetryable)
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Upload: Success (201)

    func testUploadSuccess() async throws {
        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.path.hasSuffix("/api/v1/captures"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cpx_upload_token")

            // Note: request.httpBody is nil inside URLProtocol handlers (URLSession streams it separately).
            // Body structure is validated by CaptureUploadPayloadTests instead.

            let json = """
            {
                "capture_id": "server-capture-id-456",
                "web_url": "https://wound-os.replit.app/captures/server-capture-id-456",
                "received_at": "2026-04-24T18:30:16.000Z",
                "status": "received"
            }
            """.data(using: .utf8)!

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let client = ClinicalPlatformClient(session: mockSession)
        let payload = makeTestPayload()
        let result = try await client.upload(payload: payload, token: "cpx_upload_token", baseURL: testBaseURL)

        XCTAssertEqual(result.serverCaptureId, "server-capture-id-456")
        XCTAssertEqual(result.webURL.absoluteString, "https://wound-os.replit.app/captures/server-capture-id-456")
        XCTAssertEqual(result.status, "received")
    }

    // MARK: - Upload: Bad Request (400)

    func testUploadBadRequest() async {
        URLProtocolMock.requestHandler = { request in
            let json = """
            {"error": "Missing required field: segmentation"}
            """.data(using: .utf8)!

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.upload(payload: makeTestPayload(), token: "token", baseURL: testBaseURL)
            XCTFail("Expected bad request error")
        } catch let error as ClinicalPlatformError {
            if case .badRequest(let detail) = error {
                XCTAssertTrue(detail.contains("Missing required field"))
                XCTAssertFalse(error.isRetryable)
            } else {
                XCTFail("Expected badRequest, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Upload: Unauthorized (401)

    func testUploadUnauthorized() async {
        URLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.upload(payload: makeTestPayload(), token: "expired", baseURL: testBaseURL)
            XCTFail("Expected unauthorized error")
        } catch let error as ClinicalPlatformError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Upload: Validation Error (422)

    func testUploadValidationError() async {
        URLProtocolMock.requestHandler = { request in
            let json = """
            {"error": "confidence must be between 0 and 1"}
            """.data(using: .utf8)!

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.upload(payload: makeTestPayload(), token: "token", baseURL: testBaseURL)
            XCTFail("Expected validation error")
        } catch let error as ClinicalPlatformError {
            if case .validationError(let detail) = error {
                XCTAssertTrue(detail.contains("confidence"))
                XCTAssertFalse(error.isRetryable)
            } else {
                XCTFail("Expected validationError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Upload: Payload Too Large (413)

    func testUploadPayloadTooLarge() async {
        URLProtocolMock.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 413, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.upload(payload: makeTestPayload(), token: "token", baseURL: testBaseURL)
            XCTFail("Expected payload too large error")
        } catch let error as ClinicalPlatformError {
            XCTAssertEqual(error, .payloadTooLarge)
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Upload: Server Error (503)

    func testUploadServerError() async {
        URLProtocolMock.requestHandler = { request in
            let json = """
            {"error": "Service temporarily unavailable"}
            """.data(using: .utf8)!

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.upload(payload: makeTestPayload(), token: "token", baseURL: testBaseURL)
            XCTFail("Expected server error")
        } catch let error as ClinicalPlatformError {
            if case .serverError(let code, _) = error {
                XCTAssertEqual(code, 503)
                XCTAssertTrue(error.isRetryable)
            } else {
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Upload: Network Failure

    func testUploadNetworkFailure() async {
        URLProtocolMock.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let client = ClinicalPlatformClient(session: mockSession)

        do {
            _ = try await client.upload(payload: makeTestPayload(), token: "token", baseURL: testBaseURL)
            XCTFail("Expected network error")
        } catch let error as ClinicalPlatformError {
            if case .networkError = error {
                XCTAssertTrue(error.isRetryable)
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Error Retryability

    func testErrorRetryability() {
        XCTAssertTrue(ClinicalPlatformError.serverError(500, "").isRetryable)
        XCTAssertTrue(ClinicalPlatformError.serverError(503, "").isRetryable)
        XCTAssertTrue(ClinicalPlatformError.networkError("timeout").isRetryable)

        XCTAssertFalse(ClinicalPlatformError.unauthorized.isRetryable)
        XCTAssertFalse(ClinicalPlatformError.badRequest("bad").isRetryable)
        XCTAssertFalse(ClinicalPlatformError.validationError("invalid").isRetryable)
        XCTAssertFalse(ClinicalPlatformError.payloadTooLarge.isRetryable)
        XCTAssertFalse(ClinicalPlatformError.noTokenConfigured.isRetryable)
        XCTAssertFalse(ClinicalPlatformError.noBaseURLConfigured.isRetryable)
        XCTAssertFalse(ClinicalPlatformError.noVerifiedUser.isRetryable)
    }

    // MARK: - DefaultCaptureUploader: No Token

    func testDefaultUploaderThrowsWhenNoToken() async {
        let store = InMemoryClinicalTokenStore()
        let client = ClinicalPlatformClient(session: mockSession)
        let uploader = DefaultCaptureUploader(client: client, tokenStore: store)

        do {
            _ = try await uploader.upload(makeTestCompletedCapture())
            XCTFail("Expected noTokenConfigured")
        } catch let error as ClinicalPlatformError {
            XCTAssertEqual(error, .noTokenConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - DefaultCaptureUploader: No Base URL

    func testDefaultUploaderThrowsWhenNoBaseURL() async throws {
        let store = InMemoryClinicalTokenStore(token: "cpx_test")
        let client = ClinicalPlatformClient(session: mockSession)
        let uploader = DefaultCaptureUploader(client: client, tokenStore: store)

        do {
            _ = try await uploader.upload(makeTestCompletedCapture())
            XCTFail("Expected noBaseURLConfigured")
        } catch let error as ClinicalPlatformError {
            XCTAssertEqual(error, .noBaseURLConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeTestPayload() -> CaptureUploadPayload {
        CaptureUploadPayload(
            captureId: UUID(),
            capturedAt: Date(),
            device: DevicePayload(model: "iPhone 15 Pro", osVersion: "17.5.1", appVersion: "v5-build-26"),
            capturedBy: CapturedByPayload(userId: "user-123", userName: "Test Nurse"),
            notes: "Test note",
            segmentation: SegmentationPayload(confidence: 0.94, maskCoveragePct: 4.8),
            measurements: MeasurementsPayload(
                lengthCm: 4.2, widthCm: 2.8, areaCm2: 9.1, perimeterCm: 11.4, depthCm: nil
            ),
            lidarMetadata: LiDARMetadataPayload(captureDistanceCm: 29.3, lidarConfidencePct: 87, frameCount: 12),
            artifacts: ArtifactsPayload(rgbImageBase64: "dGVzdA==", maskImageBase64: "dGVzdA==", overlayImageBase64: "dGVzdA==")
        )
    }

    private func makeTestCompletedCapture() -> CompletedCapture {
        let user = VerifiedUser(
            userId: "user-123", name: "Nurse", email: "n@t.com", role: "nurse", facilityId: "f1"
        )
        let image = UIImage()
        return CompletedCapture(
            notes: "test",
            segmentation: SegmentationPayload(confidence: 0.9, maskCoveragePct: 5.0),
            measurements: MeasurementsPayload(
                lengthCm: 4.0, widthCm: 3.0, areaCm2: 9.0, perimeterCm: 11.0, depthCm: nil
            ),
            lidarMetadata: LiDARMetadataPayload(captureDistanceCm: 30.0, lidarConfidencePct: 85, frameCount: 10),
            deviceInfo: DevicePayload(model: "Test", osVersion: "17.0", appVersion: "v5-build-1"),
            capturedByUser: user,
            rgbImage: image,
            maskImage: image,
            overlayImage: image
        )
    }
}

import XCTest
@testable import WoundNetworking

final class WoundOSClientTests: XCTestCase {

    private var mockSession: URLSession!
    private let testConfig = APIConfig(baseURL: URL(string: "https://test.example.com")!)

    override func setUp() {
        super.setUp()
        mockSession = makeMockSession()
        URLProtocolMock.requestHandler = nil
        Endpoints.config = testConfig
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        Endpoints.config = .staging
        super.tearDown()
    }

    // MARK: - Test 1: Multipart Upload Body Format

    /// Verifies 4 parts in order (rgb_image, depth_map, mesh, metadata) with correct
    /// Content-Disposition + Content-Type headers and RFC 2046 boundary terminator.
    func testMultipartUploadBodyFormat() {
        let boundary = "test-boundary-123"

        let parts: [MultipartPart] = [
            MultipartPart(name: "rgb_image", filename: "rgb.jpg", mimeType: "image/jpeg", data: Data("JPEG".utf8)),
            MultipartPart(name: "depth_map", filename: "depth.bin", mimeType: "application/octet-stream", data: Data("DEPTH".utf8)),
            MultipartPart(name: "mesh", filename: "mesh.bin", mimeType: "application/octet-stream", data: Data("MESH".utf8)),
            MultipartPart(name: "metadata", filename: "metadata.json", mimeType: "application/json", data: Data("{}".utf8)),
        ]

        let body = WoundOSClient.buildMultipartBodyStatic(parts: parts, boundary: boundary)
        let bodyString = String(data: body, encoding: .utf8)!

        // Verify 4 part boundaries + final terminator
        let partBoundaryCount = bodyString.components(separatedBy: "--\(boundary)\r\n").count - 1
        XCTAssertEqual(partBoundaryCount, 4, "Expected 4 part boundaries")

        // Verify final terminator
        XCTAssertTrue(bodyString.hasSuffix("--\(boundary)--\r\n"), "Missing RFC 2046 boundary terminator")

        // Verify parts appear in order
        let rgbRange = bodyString.range(of: "name=\"rgb_image\"")!
        let depthRange = bodyString.range(of: "name=\"depth_map\"")!
        let meshRange = bodyString.range(of: "name=\"mesh\"")!
        let metaRange = bodyString.range(of: "name=\"metadata\"")!
        XCTAssertTrue(rgbRange.lowerBound < depthRange.lowerBound, "rgb_image must come before depth_map")
        XCTAssertTrue(depthRange.lowerBound < meshRange.lowerBound, "depth_map must come before mesh")
        XCTAssertTrue(meshRange.lowerBound < metaRange.lowerBound, "mesh must come before metadata")

        // Verify Content-Types
        XCTAssertTrue(bodyString.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(bodyString.contains("Content-Type: application/octet-stream"))
        XCTAssertTrue(bodyString.contains("Content-Type: application/json"))

        // Verify filenames
        XCTAssertTrue(bodyString.contains("filename=\"rgb.jpg\""))
        XCTAssertTrue(bodyString.contains("filename=\"depth.bin\""))
        XCTAssertTrue(bodyString.contains("filename=\"mesh.bin\""))
        XCTAssertTrue(bodyString.contains("filename=\"metadata.json\""))
    }

    // MARK: - Test 2: 401 Retry with Token Refresh

    /// Simulates:
    ///   1. GET /v1/scans/{id} → 401 (first hit)
    ///   2. AuthProvider.refreshToken() → POST /v1/auth/token → new token
    ///   3. Retry GET → 200 with valid ScanResponse
    func test401RetryWithTokenRefresh() async throws {
        var scanEndpointHits = 0
        var authTokenHits = 0
        let scanId = UUID()
        let scanIdString = scanId.uuidString.lowercased()

        let scanJSON = makeScanResponseJSON(scanId: scanIdString)

        URLProtocolMock.requestHandler = { request in
            let path = request.url?.path ?? ""

            // Auth token exchange (from AuthProvider.refreshToken)
            if path.contains("auth/token") {
                authTokenHits += 1
                let tokenJSON = """
                {"token": "fresh-jwt-token-\(authTokenHits)", "expires_in": 3600}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, tokenJSON)
            }

            // Scan endpoint — first hit returns 401, subsequent return 200
            if path.contains("scans/") && !path.hasSuffix("/status") {
                scanEndpointHits += 1
                if scanEndpointHits == 1 {
                    let response = HTTPURLResponse(
                        url: request.url!, statusCode: 401,
                        httpVersion: nil, headerFields: nil
                    )!
                    return (response, Data("{}".utf8))
                }

                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, scanJSON)
            }

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let tokenStore = InMemoryTokenStore(token: "stale-token")
        let firebase = StubFirebaseAuth(token: "stub-firebase-id-token")
        let authProvider = AuthProvider(
            tokenStore: tokenStore,
            firebase: firebase,
            session: mockSession
        )
        let client = WoundOSClient(
            config: testConfig,
            session: mockSession,
            authProvider: authProvider
        )

        let result: ScanResponse = try await client.getScan(id: scanId)
        XCTAssertEqual(result.id, scanIdString)
        XCTAssertEqual(scanEndpointHits, 2, "Scan endpoint hit twice: 401 then 200")
        XCTAssertGreaterThanOrEqual(authTokenHits, 2, "Auth token exchanged at least twice: initial + after 401")
    }

    // MARK: - Test 3: Poll Until Complete Stops on "completed"

    /// Polls status, gets "processing" first, then "completed", then fetches the full scan.
    func testPollUntilCompleteStopsOnCompleted() async throws {
        var statusCallCount = 0
        let scanId = UUID()
        let scanIdString = scanId.uuidString.lowercased()

        let scanJSON = makeScanResponseJSON(scanId: scanIdString)

        URLProtocolMock.requestHandler = { request in
            let path = request.url?.path ?? ""

            // Auth token exchange
            if path.contains("auth/token") {
                let tokenJSON = """
                {"token": "test-token", "expires_in": 3600}
                """.data(using: .utf8)!
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, tokenJSON)
            }

            // Status endpoint
            if path.hasSuffix("/status") {
                statusCallCount += 1
                let status: String
                if statusCallCount == 1 {
                    status = "processing"
                } else {
                    status = "completed"
                }

                let statusJSON = """
                {
                    "scan_id": "\(scanIdString)",
                    "processing_status": "\(status)"
                }
                """.data(using: .utf8)!

                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, statusJSON)
            }

            // Full scan fetch after "completed"
            if path.contains("scans/") {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: nil
                )!
                return (response, scanJSON)
            }

            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        let tokenStore = InMemoryTokenStore(token: "test-token")
        let firebase = StubFirebaseAuth()
        let authProvider = AuthProvider(
            tokenStore: tokenStore,
            firebase: firebase,
            session: mockSession
        )
        let client = WoundOSClient(
            config: testConfig,
            session: mockSession,
            authProvider: authProvider
        )

        let result = try await client.pollUntilComplete(
            scanID: scanId,
            every: 0.05,   // 50ms for fast tests
            timeout: 10.0
        )
        XCTAssertEqual(result.id, scanIdString)
        XCTAssertEqual(statusCallCount, 2, "Should poll twice: processing then completed")
    }

    // MARK: - Test 4: Scan Response Decoding

    /// Decodes a full ScanResponse JSON payload matching the wire format from the backend,
    /// including all optional fields both present and null.
    func testScanResponseDecoding() throws {
        // Full payload — all fields present
        let fullJSON = """
        {
            "id": "abc-123",
            "patient_id": "patient-456",
            "nurse_id": "nurse-789",
            "facility_id": "facility-001",
            "captured_at": "2025-04-20T14:30:00Z",
            "upload_status": "completed",
            "area_cm2": 12.5,
            "max_depth_mm": 3.2,
            "mean_depth_mm": 1.8,
            "volume_ml": 0.45,
            "length_mm": 45.0,
            "width_mm": 30.0,
            "perimeter_mm": 120.0,
            "push_total_score": 12,
            "exudate_amount": "moderate",
            "tissue_type": "granulation",
            "agreement_metrics": {
                "iou": 0.85,
                "dice_coefficient": 0.92,
                "area_delta_percent": 5.3,
                "depth_delta_mm": 0.4,
                "volume_delta_ml": 0.05,
                "centroid_displacement_mm": 2.1,
                "sam_confidence": 0.95,
                "sam_model_version": "sam2-large-v1",
                "is_flagged": false
            },
            "clinical_summary": {
                "narrative_summary": "Wound is healing well.",
                "trajectory": "improving",
                "key_findings": ["Granulation tissue present", "Reduced exudate"],
                "recommendations": ["Continue current treatment"],
                "model_version": "gpt-4o-2024-08"
            },
            "fwa_signals": {
                "nurse_baseline_agreement": 0.88,
                "wound_size_outlier": false,
                "copy_paste_risk": 0.12,
                "longitudinal_consistency": 0.91,
                "overall_risk_score": 0.15,
                "triggered_flags": []
            },
            "review_status": "approved",
            "rgb_image_path": "gs://bucket/scans/abc-123/rgb.jpg",
            "created_at": "2025-04-20T14:30:05Z",
            "updated_at": "2025-04-20T14:35:00Z"
        }
        """.data(using: .utf8)!

        let fullScan = try JSONDecoder.woundOS.decode(ScanResponse.self, from: fullJSON)
        XCTAssertEqual(fullScan.id, "abc-123")
        XCTAssertEqual(fullScan.patientId, "patient-456")
        XCTAssertEqual(fullScan.areaCm2, 12.5)
        XCTAssertEqual(fullScan.maxDepthMm, 3.2)
        XCTAssertEqual(fullScan.pushTotalScore, 12)
        XCTAssertNotNil(fullScan.agreementMetrics)
        XCTAssertEqual(fullScan.agreementMetrics?.iou, 0.85)
        XCTAssertNotNil(fullScan.clinicalSummary)
        XCTAssertEqual(fullScan.clinicalSummary?.trajectory, "improving")
        XCTAssertNotNil(fullScan.fwaSignals)
        XCTAssertEqual(fullScan.fwaSignals?.overallRiskScore, 0.15)
        XCTAssertEqual(fullScan.reviewStatus, "approved")

        // Minimal payload — optional fields are null/absent
        let minimalJSON = """
        {
            "id": "def-456",
            "patient_id": "patient-789",
            "nurse_id": "nurse-111",
            "facility_id": "facility-002",
            "captured_at": "2025-04-20T15:00:00Z",
            "upload_status": "pending",
            "area_cm2": null,
            "max_depth_mm": null,
            "mean_depth_mm": null,
            "volume_ml": null,
            "length_mm": null,
            "width_mm": null,
            "perimeter_mm": null,
            "push_total_score": null,
            "exudate_amount": null,
            "tissue_type": null,
            "agreement_metrics": null,
            "clinical_summary": null,
            "fwa_signals": null,
            "review_status": null,
            "rgb_image_path": null,
            "created_at": "2025-04-20T15:00:01Z",
            "updated_at": "2025-04-20T15:00:01Z"
        }
        """.data(using: .utf8)!

        let minimalScan = try JSONDecoder.woundOS.decode(ScanResponse.self, from: minimalJSON)
        XCTAssertEqual(minimalScan.id, "def-456")
        XCTAssertEqual(minimalScan.uploadStatus, "pending")
        XCTAssertNil(minimalScan.areaCm2)
        XCTAssertNil(minimalScan.agreementMetrics)
        XCTAssertNil(minimalScan.clinicalSummary)
        XCTAssertNil(minimalScan.fwaSignals)
        XCTAssertNil(minimalScan.reviewStatus)
    }

    // MARK: - Test 5: Date Round-Trip

    /// Encode a date via `JSONEncoder.woundOS` → decode via `JSONDecoder.woundOS`,
    /// verify within 1 second (ISO-8601 drops sub-second precision).
    func testDateRoundTrip() throws {
        struct Wrapper: Codable {
            let capturedAt: Date
        }

        let now = Date()
        let wrapper = Wrapper(capturedAt: now)

        let encoded = try JSONEncoder.woundOS.encode(wrapper)
        let decoded = try JSONDecoder.woundOS.decode(Wrapper.self, from: encoded)

        // ISO 8601 truncates to seconds, so allow 1-second tolerance
        let delta = abs(now.timeIntervalSince(decoded.capturedAt))
        XCTAssertLessThan(delta, 1.0, "Date round-trip should be within 1 second (ISO-8601 precision)")

        // Verify the JSON string contains ISO-8601 format
        let jsonString = String(data: encoded, encoding: .utf8)!
        XCTAssertTrue(
            jsonString.contains("captured_at"),
            "Key should be snake_case: captured_at"
        )
    }

    // MARK: - Helpers

    /// Create a valid ScanResponse JSON payload for testing.
    private func makeScanResponseJSON(scanId: String) -> Data {
        """
        {
            "id": "\(scanId)",
            "patient_id": "patient-test",
            "nurse_id": "nurse-test",
            "facility_id": "facility-test",
            "captured_at": "2025-04-20T12:00:00Z",
            "upload_status": "completed",
            "area_cm2": 10.0,
            "max_depth_mm": 2.0,
            "mean_depth_mm": 1.0,
            "volume_ml": 0.3,
            "length_mm": 40.0,
            "width_mm": 25.0,
            "perimeter_mm": 100.0,
            "push_total_score": 8,
            "exudate_amount": "light",
            "tissue_type": "granulation",
            "agreement_metrics": null,
            "clinical_summary": null,
            "fwa_signals": null,
            "review_status": null,
            "rgb_image_path": null,
            "created_at": "2025-04-20T12:00:05Z",
            "updated_at": "2025-04-20T12:00:05Z"
        }
        """.data(using: .utf8)!
    }
}

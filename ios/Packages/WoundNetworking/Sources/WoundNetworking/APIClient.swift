import Foundation
import WoundCore

// MARK: - WoundOS Client

/// Actor-based HTTP client for the WoundOS backend API.
/// Handles authentication (bearer token + 401 retry), multipart uploads,
/// JSON request/response, exponential-backoff retries on 5xx, and
/// a polling helper for scan processing status.
public actor WoundOSClient {

    private let config: APIConfig
    private let session: URLSession
    private let authProvider: AuthProvider

    /// Maximum retry attempts for 5xx / transient errors (not uploads).
    private let maxRetries = 3

    public init(
        config: APIConfig = .staging,
        session: URLSession = .shared,
        authProvider: AuthProvider
    ) {
        self.config = config
        self.session = session
        self.authProvider = authProvider
        Endpoints.config = config
    }

    // MARK: - Upload Scan

    /// POST /v1/scans/upload — multipart upload of scan data.
    /// No automatic retry on failure (uploads are idempotent by scan_id,
    /// but the user should see the error and tap retry manually).
    public func uploadScan(
        rgbImage: Data,
        depthMap: Data,
        mesh: Data,
        metadata: ScanUploadMetadata
    ) async throws -> UploadResponse {
        let metadataJSON = try JSONEncoder.woundOS.encode(metadata)
        let boundary = UUID().uuidString

        let parts: [MultipartPart] = [
            MultipartPart(name: "rgb_image", filename: "rgb.jpg", mimeType: "image/jpeg", data: rgbImage),
            MultipartPart(name: "depth_map", filename: "depth.bin", mimeType: "application/octet-stream", data: depthMap),
            MultipartPart(name: "mesh", filename: "mesh.bin", mimeType: "application/octet-stream", data: mesh),
            MultipartPart(name: "metadata", filename: "metadata.json", mimeType: "application/json", data: metadataJSON),
        ]

        var request = URLRequest(url: Endpoints.uploadScan)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = buildMultipartBody(parts: parts, boundary: boundary)

        return try await authenticatedRequest(request)
    }

    /// Convenience: upload a WoundScan directly (serializes via SnapshotSerializer).
    public func uploadScan(_ scan: WoundScan) async throws -> UploadResponse {
        let parts = try SnapshotSerializer.serialize(scan)
        let boundary = UUID().uuidString

        var request = URLRequest(url: Endpoints.uploadScan)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = buildMultipartBody(parts: parts, boundary: boundary)

        return try await authenticatedRequest(request)
    }

    // MARK: - Get Scan

    /// GET /v1/scans/{id} — fetch full scan with all fields.
    public func getScan(id: UUID) async throws -> ScanResponse {
        let request = URLRequest(url: Endpoints.scan(id: id.uuidString))
        return try await authenticatedRequestWithRetry(request)
    }

    // MARK: - Get Scan Status

    /// GET /v1/scans/{id}/status — lightweight polling endpoint.
    public func getScanStatus(id: UUID) async throws -> ScanStatusResponse {
        let request = URLRequest(url: Endpoints.scanStatus(id: id.uuidString))
        return try await authenticatedRequestWithRetry(request)
    }

    // MARK: - List Scans

    /// GET /v1/patients/{patientId}/scans — list scans for a patient.
    public func listScans(forPatient patientID: String) async throws -> ScanListResponse {
        let request = URLRequest(url: Endpoints.patientScans(patientId: patientID))
        return try await authenticatedRequestWithRetry(request)
    }

    // MARK: - Submit Review

    /// PATCH /v1/scans/{scanId}/review — submit clinician review.
    public func submitReview(scanID: UUID, _ review: ReviewRequest) async throws -> ReviewResponse {
        var request = URLRequest(url: Endpoints.reviewScan(id: scanID.uuidString))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.woundOS.encode(review)
        return try await authenticatedRequestWithRetry(request)
    }

    // MARK: - Polling Helper

    /// Poll GET /v1/scans/{id}/status every `interval` until processing_status
    /// is "completed" or "failed". On "completed", fetches the full scan via
    /// GET /v1/scans/{id}. Throws `.pollingTimeout` after `timeout`.
    public func pollUntilComplete(
        scanID: UUID,
        every interval: TimeInterval = 5.0,
        timeout: TimeInterval = 90.0
    ) async throws -> ScanResponse {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

            let status = try await getScanStatus(id: scanID)

            switch status.processingStatus {
            case "completed":
                return try await getScan(id: scanID)
            case "failed":
                throw APIError.processingFailed
            default:
                continue // "pending" or "processing"
            }
        }

        throw APIError.pollingTimeout
    }

    // MARK: - Health Check

    /// GET /health — no auth required.
    public func healthCheck() async throws -> Bool {
        let request = URLRequest(url: Endpoints.health)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }

        struct HealthResponse: Decodable {
            let status: String
        }
        let health = try? JSONDecoder().decode(HealthResponse.self, from: data)
        return health?.status == "ok"
    }

    // MARK: - Authenticated Request with 401 Retry

    /// Perform an authenticated request. On 401, refreshes the token once and retries.
    private func authenticatedRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        var req = request
        let token = try await authProvider.getToken()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(req)

        // Check for 401 → re-auth → retry once
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let newToken = try await authProvider.refreshToken()
            req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await performRequest(req)
            try validateResponse(retryResponse, data: retryData)
            return try decodeResponse(retryData)
        }

        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    /// Authenticated request with exponential backoff retry on 5xx / transient errors.
    /// Used for GET/PATCH (not uploads).
    private func authenticatedRequestWithRetry<T: Decodable>(_ request: URLRequest) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let result: T = try await authenticatedRequest(request)
                return result
            } catch let error as APIError {
                switch error {
                case .server, .transport:
                    lastError = error
                    let delay = pow(2.0, Double(attempt)) // 1s, 2s, 4s
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                default:
                    throw error // 4xx (except 401 handled above) → no retry
                }
            } catch {
                lastError = error
                if attempt < maxRetries - 1,
                   let urlError = error as? URLError,
                   urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    throw error
                }
            }
        }

        throw lastError ?? APIError.server(500, "Max retries exceeded")
    }

    // MARK: - Network Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw APIError.transport(URLError(.notConnectedToInternet))
            case .timedOut:
                throw APIError.transport(URLError(.timedOut))
            default:
                throw APIError.transport(error)
            }
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 400...499:
            let detail = (try? JSONDecoder.woundOS.decode(BackendErrorResponse.self, from: data))?.detail
            throw APIError.badRequest(detail ?? "Status \(http.statusCode)")
        case 500...599:
            let detail = (try? JSONDecoder.woundOS.decode(BackendErrorResponse.self, from: data))?.detail
            throw APIError.server(http.statusCode, detail ?? "Internal server error")
        default:
            throw APIError.server(http.statusCode, "Unexpected status")
        }
    }

    private func decodeResponse<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder.woundOS.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Multipart Body Builder

    /// Build RFC 2046 multipart/form-data body from ordered parts.
    public func buildMultipartBody(parts: [MultipartPart], boundary: String) -> Data {
        Self.buildMultipartBodyStatic(parts: parts, boundary: boundary)
    }

    /// Static version for testing.
    public static func buildMultipartBodyStatic(parts: [MultipartPart], boundary: String) -> Data {
        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(part.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(part.mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(part.data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

// MARK: - Backward Compatibility

/// Type alias so existing code referencing `APIClient` still compiles.
public typealias APIClient = WoundOSClient

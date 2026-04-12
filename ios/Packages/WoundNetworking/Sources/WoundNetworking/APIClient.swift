import Foundation
import WoundCore

// MARK: - Network Errors

public enum NetworkError: Error, LocalizedError {
    case unauthorized
    case badRequest(String)
    case serverError(statusCode: Int, message: String)
    case decodingFailed(Error)
    case noConnection
    case timeout
    case uploadFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication required. Please sign in."
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noConnection:
            return "No internet connection. Scan saved locally and will upload when connected."
        case .timeout:
            return "Request timed out. Will retry automatically."
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Response

public struct APIResponse<T: Decodable>: Decodable {
    public let data: T?
    public let error: String?
    public let status: String
}

public struct UploadResponse: Decodable {
    public let scanId: String
    public let uploadStatus: String
    public let gcsPaths: GCSPaths?
}

public struct GCSPaths: Decodable {
    public let rgbImage: String
    public let depthMap: String
    public let mesh: String
    public let metadata: String
}

public struct ScanStatusResponse: Decodable {
    public let scanId: String
    public let processingStatus: String
    public let shadowMeasurement: WoundMeasurement?
    public let agreementMetrics: AgreementMetrics?
    public let clinicalSummary: ClinicalSummary?
}

// MARK: - API Client

/// Typed HTTP client for the WoundOS backend API.
/// Handles authentication, multipart uploads, and JSON responses.
public final class APIClient {

    private let session: URLSession
    private let authProvider: AuthProvider

    public init(
        session: URLSession = .shared,
        authProvider: AuthProvider = .shared
    ) {
        self.session = session
        self.authProvider = authProvider
    }

    // MARK: - Upload Scan

    /// Upload a wound scan to the backend.
    /// Returns the upload response with GCS paths.
    public func uploadScan(_ scan: WoundScan) async throws -> UploadResponse {
        let parts = try SnapshotSerializer.serialize(scan)
        let boundary = UUID().uuidString
        let token = try await authProvider.getToken()

        var request = URLRequest(url: Endpoints.uploadScan)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        request.httpBody = buildMultipartBody(parts: parts, boundary: boundary)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try JSONDecoder.woundOS.decode(UploadResponse.self, from: data)
    }

    // MARK: - Fetch Scan

    /// Fetch a scan's current state from the backend (including shadow data).
    public func fetchScan(id: String) async throws -> WoundScan {
        let token = try await authProvider.getToken()

        var request = URLRequest(url: Endpoints.scan(id: id))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try JSONDecoder.woundOS.decode(WoundScan.self, from: data)
    }

    // MARK: - Fetch Patient Scans

    /// Fetch all scans for a patient.
    public func fetchPatientScans(patientId: String) async throws -> [WoundScan] {
        let token = try await authProvider.getToken()

        var request = URLRequest(url: Endpoints.patientScans(patientId: patientId))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try JSONDecoder.woundOS.decode([WoundScan].self, from: data)
    }

    // MARK: - Check Processing Status

    /// Poll the backend for scan processing status.
    public func checkScanStatus(id: String) async throws -> ScanStatusResponse {
        let token = try await authProvider.getToken()

        var request = URLRequest(url: Endpoints.scanStatus(id: id))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        return try JSONDecoder.woundOS.decode(ScanStatusResponse.self, from: data)
    }

    // MARK: - Multipart Body Builder

    private func buildMultipartBody(parts: [MultipartPart], boundary: String) -> Data {
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

    // MARK: - Response Validation

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            throw NetworkError.unauthorized
        case 400...499:
            throw NetworkError.badRequest("Status \(httpResponse.statusCode)")
        case 500...599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: "Internal server error")
        default:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: "Unexpected status")
        }
    }
}

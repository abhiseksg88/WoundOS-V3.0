import Foundation

// MARK: - Clinical Platform Client

public actor ClinicalPlatformClient {

    public static let defaultBaseURL = URL(string: "https://wound-os.replit.app")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Verify Token

    public func verify(token: String, baseURL: URL) async throws -> VerifiedUser {
        let url = baseURL.appendingPathComponent("api/v1/auth/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data, context: "verify")

        let verifyResponse: AuthVerifyResponse
        do {
            verifyResponse = try JSONDecoder().decode(AuthVerifyResponse.self, from: data)
        } catch {
            throw ClinicalPlatformError.decodingError(error.localizedDescription)
        }

        guard verifyResponse.valid else {
            throw ClinicalPlatformError.unauthorized
        }

        let user = verifyResponse.user
        return VerifiedUser(
            userId: user.id,
            name: user.name,
            email: user.email,
            role: user.role,
            facilityId: user.facilityId,
            tokenLabel: user.tokenLabel
        )
    }

    // MARK: - Upload Capture

    public func upload(payload: CaptureUploadPayload, token: String, baseURL: URL) async throws -> UploadResult {
        let url = baseURL.appendingPathComponent("api/v1/captures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw ClinicalPlatformError.decodingError("Failed to encode payload: \(error.localizedDescription)")
        }
        request.httpBody = body

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data, context: "upload")

        let uploadResponse: CaptureUploadResponse
        do {
            uploadResponse = try JSONDecoder().decode(CaptureUploadResponse.self, from: data)
        } catch {
            throw ClinicalPlatformError.decodingError(error.localizedDescription)
        }

        guard let webURL = URL(string: uploadResponse.webUrl) else {
            throw ClinicalPlatformError.decodingError("Invalid web_url in response: \(uploadResponse.webUrl)")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let uploadedAt = isoFormatter.date(from: uploadResponse.receivedAt) ?? Date()

        return UploadResult(
            captureId: UUID(uuidString: payload.captureId) ?? UUID(),
            serverCaptureId: uploadResponse.captureId,
            webURL: webURL,
            uploadedAt: uploadedAt,
            status: uploadResponse.status
        )
    }

    // MARK: - Network Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw ClinicalPlatformError.networkError(error.localizedDescription)
        } catch {
            throw ClinicalPlatformError.networkError(error.localizedDescription)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data, context: String) throws {
        guard let http = response as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw ClinicalPlatformError.unauthorized
        case 413:
            throw ClinicalPlatformError.payloadTooLarge
        case 400:
            let detail = parseErrorDetail(from: data) ?? "Bad request"
            throw ClinicalPlatformError.badRequest(detail)
        case 422:
            let detail = parseErrorDetail(from: data) ?? "Validation failed"
            throw ClinicalPlatformError.validationError(detail)
        case 500...599:
            let detail = parseErrorDetail(from: data) ?? "Internal server error"
            throw ClinicalPlatformError.serverError(http.statusCode, detail)
        default:
            let detail = parseErrorDetail(from: data) ?? "Unexpected status \(http.statusCode)"
            throw ClinicalPlatformError.serverError(http.statusCode, detail)
        }
    }

    private func parseErrorDetail(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            let error: String?
            let message: String?
            let detail: String?
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return body.error ?? body.message ?? body.detail
        }
        return nil
    }
}

import Foundation

public extension Notification.Name {
    static let clinicalPlatformDiagnostic = Notification.Name("clinicalPlatformDiagnostic")
}

// MARK: - Clinical Platform Client

public actor ClinicalPlatformClient {

    public static let defaultBaseURL = URL(string: "https://wound-os.replit.app")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Login with CarePlix ID + Passcode

    public func login(carePlixId: String, passcode: String, baseURL: URL) async throws -> LoginResponse {
        let url = baseURL.appendingPathComponent("api/v1/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: String] = [
            "careplix_id": carePlixId,
            "passcode": passcode
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logDiagnostic("[login] URL: \(url.absoluteString)")
        logDiagnostic("[login] CarePlix ID: \(carePlixId)")

        let (data, response) = try await performRequest(request)

        guard let http = response as? HTTPURLResponse else {
            throw ClinicalPlatformError.networkError("Invalid response")
        }

        logDiagnostic("[login] Status: \(http.statusCode)")

        let bodyString = String(data: data, encoding: .utf8) ?? "(non-UTF8, \(data.count) bytes)"
        logDiagnostic("[login] Body: \(bodyString.prefix(500))")

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw ClinicalPlatformError.invalidCredentials
        case 404:
            throw ClinicalPlatformError.networkError("Login endpoint not found. Check API Base URL.")
        case 500...599:
            throw ClinicalPlatformError.serverError(http.statusCode, "Server error")
        default:
            throw ClinicalPlatformError.serverError(http.statusCode, "Unexpected status \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(LoginResponse.self, from: data)
        } catch {
            logDiagnostic("[login] Decode FAILED: \(error)")
            throw ClinicalPlatformError.decodingError(
                "\(error.localizedDescription). Raw: \(bodyString.prefix(200))"
            )
        }
    }

    // MARK: - Verify Token

    public func verify(token: String, baseURL: URL) async throws -> VerifiedUser {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = baseURL.appendingPathComponent("api/v1/auth/verify")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let maskedToken = maskToken(trimmedToken)
        logDiagnostic("[verify] URL: \(url.absoluteString)")
        logDiagnostic("[verify] Method: POST")
        logDiagnostic("[verify] Auth: Bearer \(maskedToken)")

        let (data, response) = try await performRequest(request)

        guard let http = response as? HTTPURLResponse else {
            throw ClinicalPlatformError.networkError("Invalid response")
        }

        logDiagnostic("[verify] Status: \(http.statusCode)")
        logDiagnostic("[verify] Content-Type: \(http.value(forHTTPHeaderField: "Content-Type") ?? "nil")")

        let bodyString = String(data: data, encoding: .utf8) ?? "(non-UTF8, \(data.count) bytes)"
        logDiagnostic("[verify] Body: \(bodyString.prefix(500))")

        switch http.statusCode {
        case 200:
            break
        case 401:
            struct ErrorResponse: Decodable { let error: String? }
            let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let message = errorBody?.error ?? "Authentication failed"
            throw ClinicalPlatformError.unauthorized
        case 404:
            throw ClinicalPlatformError.networkError("Endpoint not found. Check API Base URL.")
        case 500...599:
            throw ClinicalPlatformError.serverError(http.statusCode, "Server error")
        default:
            throw ClinicalPlatformError.serverError(http.statusCode, "Unexpected status \(http.statusCode)")
        }

        let verifyResponse: AuthVerifyResponse
        do {
            verifyResponse = try JSONDecoder().decode(AuthVerifyResponse.self, from: data)
        } catch {
            logDiagnostic("[verify] Decode FAILED: \(error)")
            throw ClinicalPlatformError.decodingError(
                "\(error.localizedDescription). Raw: \(bodyString.prefix(200))"
            )
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
            tokenLabel: verifyResponse.tokenLabel
        )
    }

    private func maskToken(_ token: String) -> String {
        guard token.count > 10 else { return "***" }
        let prefix = String(token.prefix(6))
        let suffix = String(token.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    private func logDiagnostic(_ message: String) {
        #if DEBUG
        print("[ClinicalPlatformClient] \(message)")
        #endif
        NotificationCenter.default.post(
            name: .clinicalPlatformDiagnostic,
            object: nil,
            userInfo: ["message": message]
        )
    }

    // MARK: - Upload Capture

    public func upload(payload: CaptureUploadPayload, token: String, baseURL: URL) async throws -> UploadResult {
        let url = baseURL.appendingPathComponent("api/v1/captures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        logDiagnostic("[upload] URL: \(url.absoluteString)")
        logDiagnostic("[upload] Auth: Bearer \(maskToken(token))")

        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            logDiagnostic("[upload] Encode FAILED: \(error)")
            throw ClinicalPlatformError.decodingError("Failed to encode payload: \(error.localizedDescription)")
        }
        request.httpBody = body
        logDiagnostic("[upload] Body size: \(body.count) bytes")

        let (data, response) = try await performRequest(request)

        if let http = response as? HTTPURLResponse {
            logDiagnostic("[upload] Status: \(http.statusCode)")
            let bodyStr = String(data: data, encoding: .utf8) ?? "(non-UTF8, \(data.count) bytes)"
            logDiagnostic("[upload] Response: \(bodyStr.prefix(500))")
        }

        try validateResponse(response, data: data, context: "upload")

        let uploadResponse: CaptureUploadResponse
        do {
            uploadResponse = try JSONDecoder().decode(CaptureUploadResponse.self, from: data)
        } catch {
            logDiagnostic("[upload] Decode FAILED: \(error)")
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

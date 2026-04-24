import Foundation

public struct VerifiedUser: Codable, Sendable, Equatable {
    public let userId: String
    public let name: String
    public let email: String
    public let role: String
    public let facilityId: String
    public let tokenLabel: String?

    public init(
        userId: String,
        name: String,
        email: String,
        role: String,
        facilityId: String,
        tokenLabel: String? = nil
    ) {
        self.userId = userId
        self.name = name
        self.email = email
        self.role = role
        self.facilityId = facilityId
        self.tokenLabel = tokenLabel
    }
}

struct AuthVerifyResponse: Decodable {
    let valid: Bool
    let user: AuthVerifyUser

    struct AuthVerifyUser: Decodable {
        let id: String
        let name: String
        let email: String
        let role: String
        let facilityId: String
        let tokenLabel: String?

        enum CodingKeys: String, CodingKey {
            case id, name, email, role
            case facilityId = "facility_id"
            case tokenLabel = "token_label"
        }
    }
}

struct CaptureUploadResponse: Decodable {
    let captureId: String
    let webUrl: String
    let receivedAt: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case captureId = "capture_id"
        case webUrl = "web_url"
        case receivedAt = "received_at"
        case status
    }
}

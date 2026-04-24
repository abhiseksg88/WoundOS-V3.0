import Foundation

public enum ClinicalPlatformError: Error, Equatable, LocalizedError, Sendable {
    case noTokenConfigured
    case noBaseURLConfigured
    case noVerifiedUser
    case invalidBaseURL(String)
    case unauthorized
    case badRequest(String)
    case validationError(String)
    case payloadTooLarge
    case serverError(Int, String)
    case networkError(String)
    case decodingError(String)
    case keychainSaveFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .noTokenConfigured:
            return "No Clinical Platform token configured. Go to Settings to connect."
        case .noBaseURLConfigured:
            return "No Clinical Platform API URL configured."
        case .noVerifiedUser:
            return "Please verify your token in Settings before uploading."
        case .invalidBaseURL(let url):
            return "Invalid API URL: \(url)"
        case .unauthorized:
            return "Invalid or expired token. Please reconfigure in Settings."
        case .badRequest(let detail):
            return "Upload rejected: \(detail)"
        case .validationError(let detail):
            return "Validation error: \(detail)"
        case .payloadTooLarge:
            return "Capture data exceeds server size limit."
        case .serverError(let code, let detail):
            return "Server error (\(code)): \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .decodingError(let detail):
            return "Failed to parse server response: \(detail)"
        case .keychainSaveFailed(let status):
            return "Keychain save failed (status \(status))."
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .serverError, .networkError:
            return true
        case .unauthorized, .badRequest, .validationError, .payloadTooLarge,
             .noTokenConfigured, .noBaseURLConfigured, .noVerifiedUser,
             .invalidBaseURL, .decodingError, .keychainSaveFailed:
            return false
        }
    }
}

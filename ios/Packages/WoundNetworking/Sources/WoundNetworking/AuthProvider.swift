import Foundation

// MARK: - Auth Provider

/// Manages authentication tokens for API requests.
/// Wraps Firebase Auth and provides bearer tokens.
public final class AuthProvider {

    public static let shared = AuthProvider()

    private var cachedToken: String?
    private var tokenExpiry: Date?

    private init() {}

    /// Get a valid bearer token for API requests.
    /// Refreshes automatically if expired.
    public func getToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        return try await refreshToken()
    }

    /// Set the token directly (e.g., from Firebase Auth callback)
    public func setToken(_ token: String, expiresIn seconds: TimeInterval) {
        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(seconds - 60) // Refresh 60s before expiry
    }

    /// Clear cached token on logout
    public func clearToken() {
        cachedToken = nil
        tokenExpiry = nil
    }

    private func refreshToken() async throws -> String {
        // In production this would call Firebase Auth to get a fresh ID token.
        // For now, return the cached token or throw.
        guard let token = cachedToken else {
            throw NetworkError.unauthorized
        }
        return token
    }
}

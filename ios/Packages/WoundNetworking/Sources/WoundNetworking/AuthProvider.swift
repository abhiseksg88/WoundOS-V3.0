import Foundation

// MARK: - Firebase Auth Protocol

/// Abstraction over Firebase Auth for dependency injection.
/// In production, the conforming type calls `Auth.auth().currentUser?.getIDToken()`.
/// For staging / tests, a stub returns a placeholder token.
public protocol FirebaseAuthProviding: Sendable {
    func getFirebaseIDToken() async throws -> String
}

/// Stub that returns a fixed token string.
/// Use in staging (backend short-circuits Firebase verification when ENVIRONMENT=development).
public struct StubFirebaseAuth: FirebaseAuthProviding {
    private let token: String

    public init(token: String = "stub-firebase-id-token") {
        self.token = token
    }

    public func getFirebaseIDToken() async throws -> String {
        token
    }
}

// MARK: - Auth Provider

/// Manages API bearer tokens: stores in Keychain, exchanges Firebase ID tokens,
/// and refreshes on 401.
public final class AuthProvider: @unchecked Sendable {

    private let tokenStore: TokenStoreProtocol
    private let firebase: FirebaseAuthProviding
    private let session: URLSession

    /// In-memory cache to avoid Keychain reads on every request.
    private let lock = NSLock()
    private var cachedToken: String?
    private var tokenExpiry: Date?

    public init(
        tokenStore: TokenStoreProtocol,
        firebase: FirebaseAuthProviding,
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.firebase = firebase
        self.session = session
        self.cachedToken = tokenStore.loadToken()
    }

    /// Returns a valid bearer token, refreshing if needed.
    public func getToken() async throws -> String {
        lock.lock()
        let cached = cachedToken
        let expiry = tokenExpiry
        lock.unlock()

        if let token = cached, let exp = expiry, Date() < exp {
            return token
        }
        // Refresh via Firebase → backend exchange
        return try await refreshToken()
    }

    /// Force a token refresh: get a new Firebase ID token, exchange it for an API JWT.
    @discardableResult
    public func refreshToken() async throws -> String {
        let firebaseToken = try await firebase.getFirebaseIDToken()
        let response = try await exchangeFirebaseToken(firebaseToken)
        cacheToken(response.token, expiresIn: TimeInterval(response.expiresIn))
        return response.token
    }

    /// Clear all token state (logout).
    public func clearToken() {
        lock.lock()
        cachedToken = nil
        tokenExpiry = nil
        lock.unlock()
        tokenStore.deleteToken()
    }

    // MARK: - Token Exchange

    /// POST /v1/auth/token — exchange a Firebase ID token for an API JWT.
    private func exchangeFirebaseToken(_ idToken: String) async throws -> TokenResponse {
        var request = URLRequest(url: Endpoints.authToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.woundOS.encode(TokenRequest(firebaseToken: idToken))

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport(URLError(.badServerResponse))
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            let detail = (try? JSONDecoder.woundOS.decode(BackendErrorResponse.self, from: data))?.detail
            throw APIError.server(http.statusCode, detail ?? "Token exchange failed")
        }

        return try JSONDecoder.woundOS.decode(TokenResponse.self, from: data)
    }

    // MARK: - Cache

    private func cacheToken(_ token: String, expiresIn seconds: TimeInterval) {
        lock.lock()
        cachedToken = token
        tokenExpiry = Date().addingTimeInterval(seconds - 60) // Refresh 60s early
        lock.unlock()
        try? tokenStore.save(token: token)
    }
}

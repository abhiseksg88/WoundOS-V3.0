import Foundation
import Security

public protocol ClinicalPlatformTokenStore: Sendable {
    func saveToken(_ token: String) throws
    func loadToken() -> String?
    func deleteToken()
    func saveBaseURL(_ urlString: String) throws
    func loadBaseURL() -> String?
    func saveVerifiedUser(_ user: VerifiedUser) throws
    func loadVerifiedUser() -> VerifiedUser?
    func deleteVerifiedUser()
}

public final class ClinicalPlatformKeychain: ClinicalPlatformTokenStore, @unchecked Sendable {

    private let service: String
    private let tokenAccount: String
    private let baseURLAccount: String
    private let userAccount: String

    public init(
        service: String = "com.woundos.clinical-platform",
        tokenAccount: String = "cpx-bearer-token",
        baseURLAccount: String = "api-base-url",
        userAccount: String = "verified-user"
    ) {
        self.service = service
        self.tokenAccount = tokenAccount
        self.baseURLAccount = baseURLAccount
        self.userAccount = userAccount
    }

    // MARK: - Token

    public func saveToken(_ token: String) throws {
        try saveData(token.data(using: .utf8), account: tokenAccount)
    }

    public func loadToken() -> String? {
        guard let data = loadData(account: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func deleteToken() {
        deleteItem(account: tokenAccount)
    }

    // MARK: - Base URL

    public func saveBaseURL(_ urlString: String) throws {
        try saveData(urlString.data(using: .utf8), account: baseURLAccount)
    }

    public func loadBaseURL() -> String? {
        guard let data = loadData(account: baseURLAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Verified User

    public func saveVerifiedUser(_ user: VerifiedUser) throws {
        let data = try JSONEncoder().encode(user)
        try saveData(data, account: userAccount)
    }

    public func loadVerifiedUser() -> VerifiedUser? {
        guard let data = loadData(account: userAccount) else { return nil }
        return try? JSONDecoder().decode(VerifiedUser.self, from: data)
    }

    public func deleteVerifiedUser() {
        deleteItem(account: userAccount)
    }

    // MARK: - Generic Keychain Operations

    private func saveData(_ data: Data?, account: String) throws {
        deleteItem(account: account)
        guard let data else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ClinicalPlatformError.keychainSaveFailed(status)
        }
    }

    private func loadData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - In-Memory Store (for tests)

public final class InMemoryClinicalTokenStore: ClinicalPlatformTokenStore, @unchecked Sendable {
    private var token: String?
    private var baseURL: String?
    private var user: VerifiedUser?

    public init(token: String? = nil, baseURL: String? = nil, user: VerifiedUser? = nil) {
        self.token = token
        self.baseURL = baseURL
        self.user = user
    }

    public func saveToken(_ token: String) throws { self.token = token }
    public func loadToken() -> String? { token }
    public func deleteToken() { token = nil }
    public func saveBaseURL(_ urlString: String) throws { self.baseURL = urlString }
    public func loadBaseURL() -> String? { baseURL }
    public func saveVerifiedUser(_ user: VerifiedUser) throws { self.user = user }
    public func loadVerifiedUser() -> VerifiedUser? { user }
    public func deleteVerifiedUser() { user = nil }
}

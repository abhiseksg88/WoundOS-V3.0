import Foundation
import Security

// MARK: - Token Store Protocol

public protocol TokenStoreProtocol: Sendable {
    func save(token: String) throws
    func loadToken() -> String?
    func deleteToken()
}

// MARK: - Keychain Token Store

/// Persists the API bearer token in the iOS Keychain.
/// Uses kSecClassGenericPassword with a fixed service identifier.
public final class KeychainTokenStore: TokenStoreProtocol, @unchecked Sendable {

    private let service: String
    private let account: String

    public init(service: String = "com.woundos.api", account: String = "bearer-token") {
        self.service = service
        self.account = account
    }

    public func save(token: String) throws {
        // Delete any existing token first
        deleteToken()

        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - In-Memory Token Store (for tests)

/// In-memory token store for unit testing. Not persisted.
public final class InMemoryTokenStore: TokenStoreProtocol, @unchecked Sendable {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func save(token: String) throws {
        self.token = token
    }

    public func loadToken() -> String? {
        token
    }

    public func deleteToken() {
        token = nil
    }
}

// MARK: - Keychain Error

public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status \(status)"
        }
    }
}

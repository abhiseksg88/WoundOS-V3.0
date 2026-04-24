import XCTest
@testable import CaptureSync

final class ClinicalPlatformKeychainTests: XCTestCase {

    // MARK: - In-Memory Token Store Tests

    func testTokenSaveAndLoad() throws {
        let store = InMemoryClinicalTokenStore()
        XCTAssertNil(store.loadToken())

        try store.saveToken("cpx_test_token_12345")
        XCTAssertEqual(store.loadToken(), "cpx_test_token_12345")
    }

    func testTokenOverwrite() throws {
        let store = InMemoryClinicalTokenStore()
        try store.saveToken("cpx_first")
        try store.saveToken("cpx_second")
        XCTAssertEqual(store.loadToken(), "cpx_second")
    }

    func testTokenDelete() throws {
        let store = InMemoryClinicalTokenStore()
        try store.saveToken("cpx_to_delete")
        XCTAssertNotNil(store.loadToken())

        store.deleteToken()
        XCTAssertNil(store.loadToken())
    }

    func testDeleteWhenEmpty() {
        let store = InMemoryClinicalTokenStore()
        store.deleteToken()
        XCTAssertNil(store.loadToken())
    }

    // MARK: - Base URL Store Tests

    func testBaseURLSaveAndLoad() throws {
        let store = InMemoryClinicalTokenStore()
        XCTAssertNil(store.loadBaseURL())

        try store.saveBaseURL("https://wound-os.replit.app")
        XCTAssertEqual(store.loadBaseURL(), "https://wound-os.replit.app")
    }

    // MARK: - Verified User Store Tests

    func testVerifiedUserSaveAndLoad() throws {
        let store = InMemoryClinicalTokenStore()
        let user = VerifiedUser(
            userId: "user-123",
            name: "Test Nurse",
            email: "nurse@test.com",
            role: "nurse",
            facilityId: "facility-001",
            tokenLabel: "iOS integration test token"
        )

        try store.saveVerifiedUser(user)
        let loaded = store.loadVerifiedUser()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.userId, "user-123")
        XCTAssertEqual(loaded?.name, "Test Nurse")
        XCTAssertEqual(loaded?.role, "nurse")
        XCTAssertEqual(loaded?.facilityId, "facility-001")
        XCTAssertEqual(loaded?.tokenLabel, "iOS integration test token")
    }

    func testVerifiedUserDelete() throws {
        let store = InMemoryClinicalTokenStore()
        let user = VerifiedUser(
            userId: "user-123",
            name: "Test Nurse",
            email: "nurse@test.com",
            role: "nurse",
            facilityId: "facility-001"
        )
        try store.saveVerifiedUser(user)
        XCTAssertNotNil(store.loadVerifiedUser())

        store.deleteVerifiedUser()
        XCTAssertNil(store.loadVerifiedUser())
    }

    func testInitWithPreloadedValues() {
        let user = VerifiedUser(
            userId: "u1", name: "N", email: "e", role: "r", facilityId: "f"
        )
        let store = InMemoryClinicalTokenStore(
            token: "cpx_preloaded",
            baseURL: "https://example.com",
            user: user
        )
        XCTAssertEqual(store.loadToken(), "cpx_preloaded")
        XCTAssertEqual(store.loadBaseURL(), "https://example.com")
        XCTAssertEqual(store.loadVerifiedUser()?.userId, "u1")
    }
}

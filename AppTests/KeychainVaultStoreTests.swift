import Security
import XCTest
@testable import IntervalTracker

final class KeychainVaultStoreTests: XCTestCase {
    /// An app that is not signed has no Keychain: every write fails with `errSecMissingEntitlement`.
    /// CI builds the tests that way, so these two run only in a signed build.
    override func setUpWithError() throws {
        let probe: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: "KeychainVaultStoreTests",
            kSecAttrAccount: UUID().uuidString, kSecValueData: Data(),
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete(probe as CFDictionary)
        try XCTSkipIf(status == errSecMissingEntitlement, "this build is not signed, so it has no Keychain")
    }

    func testTheVaultComesBackFromTheKeychainAsItWentIn() {
        let store = KeychainVaultStore(account: "test-\(UUID().uuidString)")
        defer { store.delete() }
        XCTAssertNil(store.load())

        var vault = Vault(clientID: "oaiapp_1", session: Vault.Session(
            accessToken: "access-1", refreshToken: "refresh-1", scope: fullScope,
            expiresAt: Date(timeIntervalSinceReferenceDate: 800_000_000), email: "you@example.com"), apiKey: "sk-test")
        store.save(vault)
        XCTAssertEqual(store.load(), vault)

        vault.session?.refreshToken = "refresh-2"
        vault.apiKey = nil
        store.save(vault)
        XCTAssertEqual(store.load(), vault, "a second save replaces the first")

        store.delete()
        XCTAssertNil(store.load())
    }

    func testTwoAccountNamesAreTwoItems() {
        let first = KeychainVaultStore(account: "test-\(UUID().uuidString)")
        let second = KeychainVaultStore(account: "test-\(UUID().uuidString)")
        defer {
            first.delete()
            second.delete()
        }
        first.save(Vault(apiKey: "sk-first"))
        XCTAssertNil(second.load())
        XCTAssertEqual(first.load()?.apiKey, "sk-first")
    }
}

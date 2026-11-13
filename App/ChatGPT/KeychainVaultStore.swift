import Foundation
import Security

/// The vault as one generic-password item. It is readable after the first unlock, so a token can be
/// refreshed while the phone is locked, and it never leaves this device in a backup.
struct KeychainVaultStore: VaultStore {
    var account = "vault"

    private var item: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.kron00.IntervalTracker.chatgpt",
            kSecAttrAccount: account,
        ]
    }

    func load() -> Vault? {
        var query = item
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Vault.self, from: data)
    }

    func save(_ vault: Vault) {
        guard let data = try? JSONEncoder().encode(vault) else { return }
        guard SecItemUpdate(item as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound else { return }
        var new = item
        new[kSecValueData] = data
        new[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(new as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(item as CFDictionary)
    }
}

/// A vault that lives only as long as the app runs. The `-aiStub` launch argument and the tests use it.
final class MemoryVaultStore: VaultStore, @unchecked Sendable {
    private let lock = NSLock()
    private var vault: Vault?

    init(_ vault: Vault? = nil) {
        self.vault = vault
    }

    func load() -> Vault? {
        lock.withLock { vault }
    }

    func save(_ vault: Vault) {
        lock.withLock { self.vault = vault }
    }
}

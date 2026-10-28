import Foundation
import Security

public enum CredentialStore {
    private static let service = "com.smidley.RecompTV.sources"

    public static func load(_ id: UUID) throws -> String {
        var query = base(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw LibraryError.message("Could not read the saved credential from Keychain (\(status)).")
        }
        return value
    }

    public static func save(_ secret: String, for id: UUID) throws {
        let query = base(id)
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw LibraryError.message("Could not save the credential in Keychain (\(added)).")
            }
        } else if status != errSecSuccess {
            throw LibraryError.message("Could not update the saved credential (\(status)).")
        }
    }

    public static func remove(_ id: UUID) throws {
        let status = SecItemDelete(base(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LibraryError.message("Could not remove the saved credential (\(status)).")
        }
    }

    private static func base(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString,
         kSecAttrSynchronizable as String: false]
    }
}

import Foundation
import Security
import GevunCore

enum Credentials {
    private static let service = "app.gevun.music.instances"
    private static let account = "saved-servers"
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() throws -> [Instance] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialError.unavailable }
        do { return try JSONDecoder().decode([Instance].self, from: data) } catch { throw CredentialError.unavailable }
    }

    static func save(_ instances: [Instance]) throws {
        let data = try JSONEncoder().encode(instances)
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            changes.forEach { item[$0] = $1 }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CredentialError.unavailable }
        } else if status != errSecSuccess {
            throw CredentialError.unavailable
        }
    }
}
enum CredentialError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "Gevun could not access saved credentials in Keychain. Unlock your device and try again."
    }
}

import Foundation
import Security

public struct KeychainStore {
    private let service = "com.local.consolepilot"
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: String] = [:]
    }
    private static let cache = Cache()

    public init() {}

    public func read(name: String) throws -> String {
        Self.cache.lock.lock()
        let cached = Self.cache.values[name]
        Self.cache.lock.unlock()
        if let cached { return cached }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        // Keychain Access may create an item without our service label (for
        // example, an application password whose account is the profile key).
        // Keep the namespaced lookup first, then allow an exact-account
        // fallback so existing user-created entries remain usable.
        if status == errSecItemNotFound {
            let accountQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: name,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]
            result = nil
            status = SecItemCopyMatching(accountQuery as CFDictionary, &result)
        }
        if status == errSecItemNotFound {
            let labelQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrLabel: name,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne,
            ]
            result = nil
            status = SecItemCopyMatching(labelQuery as CFDictionary, &result)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        Self.cache.lock.lock()
        Self.cache.values[name] = value
        Self.cache.lock.unlock()
        return value
    }

    func write(name: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
        Self.cache.lock.lock()
        Self.cache.values[name] = value
        Self.cache.lock.unlock()
    }

    func delete(name: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        Self.cache.lock.lock()
        Self.cache.values.removeValue(forKey: name)
        Self.cache.lock.unlock()
    }

    func exists(name: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: name,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

}

struct KeychainError: Error, Equatable, Sendable {
    let status: OSStatus
}

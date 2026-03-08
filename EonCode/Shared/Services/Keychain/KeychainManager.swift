import Foundation
import Security

final class KeychainManager {
    static let shared = KeychainManager()

    private let service = Constants.Keychain.service
    private let accessGroup = Constants.Keychain.accessGroup

    private init() {}

    // MARK: - CRUD
    func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func get(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.notFound(key)
        }

        return string
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    func exists(key: String) -> Bool {
        (try? get(key: key)) != nil
    }

    func listAll() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return [] }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Convenience (iCloud-synced API keys)

    var anthropicAPIKey: String? {
        // Prefer synced value, fall back to local
        KeychainSync.getSync(key: Constants.Keychain.anthropicKey)
            ?? (try? get(key: Constants.Keychain.anthropicKey))
    }

    func saveAnthropicKey(_ key: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.anthropicKey, value: key)
    }

    var elevenLabsAPIKey: String? {
        KeychainSync.getSync(key: Constants.Keychain.elevenLabsKey)
            ?? (try? get(key: Constants.Keychain.elevenLabsKey))
    }

    func saveElevenLabsKey(_ key: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.elevenLabsKey, value: key)
    }

    var muxAPIKey: String? {
        KeychainSync.getSync(key: Constants.Keychain.muxKey)
            ?? (try? get(key: Constants.Keychain.muxKey))
    }

    func saveMuxKey(_ key: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.muxKey, value: key)
    }

    var githubToken: String? {
        KeychainSync.getSync(key: Constants.Keychain.githubKey)
            ?? (try? get(key: Constants.Keychain.githubKey))
    }

    func saveGitHubToken(_ token: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.githubKey, value: token)
    }

    var xaiAPIKey: String? {
        KeychainSync.getSync(key: Constants.Keychain.xaiKey)
            ?? (try? get(key: Constants.Keychain.xaiKey))
    }

    func saveXAIKey(_ key: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.xaiKey, value: key)
    }

    func getKey(for service: String) -> String? {
        try? get(key: service)
    }

    func saveKey(_ value: String, for service: String) throws {
        try save(key: service, value: value)
    }

    // MARK: - Custom API keys (user-defined, iCloud-synced)

    private static let customPrefix = "custom_"
    private static let customIndexKey = "custom_index"

    /// Save a custom key by name. Both the value and the index are iCloud-synced.
    func saveCustomKey(name: String, value: String) throws {
        let storageKey = Self.customPrefix + name
        try KeychainSync.saveSync(key: storageKey, value: value)
        // Update the index of known custom key names
        var index = customKeyNames()
        if !index.contains(name) {
            index.append(name)
            let indexValue = index.joined(separator: "\n")
            try KeychainSync.saveSync(key: Self.customIndexKey, value: indexValue)
        }
    }

    /// Retrieve a custom key value by name.
    func getCustomKey(name: String) -> String? {
        KeychainSync.getSync(key: Self.customPrefix + name)
    }

    /// Delete a custom key by name.
    func deleteCustomKey(name: String) {
        KeychainSync.deleteSync(key: Self.customPrefix + name)
        var index = customKeyNames()
        index.removeAll { $0 == name }
        let indexValue = index.joined(separator: "\n")
        try? KeychainSync.saveSync(key: Self.customIndexKey, value: indexValue)
    }

    /// Returns all custom key names (from the synced index).
    func customKeyNames() -> [String] {
        guard let raw = KeychainSync.getSync(key: Self.customIndexKey), !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// Returns all custom keys as name→value pairs.
    func allCustomKeys() -> [(name: String, value: String)] {
        customKeyNames().compactMap { name in
            guard let value = getCustomKey(name: name) else { return nil }
            return (name: name, value: value)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status): return "Keychain save failed: \(status)"
        case .notFound(let key): return "Key not found in keychain: \(key)"
        }
    }
}

//
//  KeychainStore.swift
//  macflare
//
//  Secure persistence for the OAuth token using the macOS Keychain.
//

import Foundation
import Security

/// Injectable storage keeps lifecycle tests away from the user's Keychain.
@MainActor
protocol AuthTokenStoring {
    func save(_ token: AuthToken) throws
    func load() throws -> AuthToken?
    func delete() throws
}

/// Minimal, secure persistence for the OAuth token using the macOS Keychain.
///
/// Tokens are sensitive, so they are never written to `UserDefaults` or logs. A
/// single generic-password item holds the JSON-encoded ``AuthToken``.
struct KeychainStore: AuthTokenStoring {
    enum KeychainError: Error, LocalizedError, Equatable {
        case unexpectedStatus(OSStatus)
        case invalidStoredData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "The saved Cloudflare session could not be accessed in Keychain (status \(status))."
            case .invalidStoredData:
                return "The saved Cloudflare session in Keychain is unreadable. Sign out to remove it, then sign in again."
            }
        }
    }

    let service: String
    let account: String

    init(service: String = "com.macflare.oauth", account: String = "cloudflare-token") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves (or replaces) the token. The item is accessible only after first
    /// unlock and never syncs to other devices.
    func save(_ token: AuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Loads the persisted token, or `nil` if none is stored.
    func load() throws -> AuthToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError.invalidStoredData }
            do {
                return try JSONDecoder().decode(AuthToken.self, from: data)
            } catch {
                throw KeychainError.invalidStoredData
            }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the persisted token (used on sign-out).
    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

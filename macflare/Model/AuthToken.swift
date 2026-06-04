//
//  AuthToken.swift
//  macflare
//
//  OAuth token set returned by Cloudflare's token endpoint.
//

import Foundation

/// An OAuth token set returned by Cloudflare's token endpoint.
///
/// Conforms to `Codable` so it can be parsed from the token response and
/// persisted to the Keychain, and to `Hashable` per project model conventions.
struct AuthToken: Codable, Hashable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scope: String?
    /// Absolute expiry time, derived from `expires_in` at decode time.
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case expiresAt
    }

    init(
        accessToken: String,
        refreshToken: String?,
        tokenType: String,
        scope: String?,
        expiresAt: Date?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.scope = scope
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "Bearer"
        scope = try container.decodeIfPresent(String.self, forKey: .scope)

        // Prefer a precomputed absolute expiry (when re-decoding from the
        // Keychain), otherwise derive it from the relative `expires_in` seconds
        // returned by the token endpoint.
        if let absolute = try container.decodeIfPresent(Date.self, forKey: .expiresAt) {
            expiresAt = absolute
        } else if let expiresIn = try container.decodeIfPresent(Double.self, forKey: .expiresIn) {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }

    /// Whether the access token is expired (or about to expire within `leeway`).
    func isExpired(leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return Date().addingTimeInterval(leeway) >= expiresAt
    }
}

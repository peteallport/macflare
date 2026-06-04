//
//  CloudflareAPIClient.swift
//  macflare
//
//  Thin REST client that injects the OAuth bearer token.
//

import Foundation

/// Thin client for the Cloudflare REST API that injects the OAuth bearer token.
///
/// The token is supplied lazily via ``tokenProvider`` so the caller (the auth
/// manager) can transparently refresh an expired access token before each call.
struct CloudflareAPIClient {
    /// Returns a currently-valid access token, refreshing if necessary.
    let tokenProvider: () async throws -> String
    var session: URLSession = .shared

    /// Verifies the current token by listing accounts. Returns the account
    /// identifiers on success; throws ``OAuthError/server(_:)`` on failure.
    @discardableResult
    func verifyToken() async throws -> [String] {
        let url = CloudflareOAuthConfig.apiBaseURL.appendingPathComponent("accounts")
        var request = URLRequest(url: url)
        let token = try await tokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.server("Invalid response from Cloudflare.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.server("Cloudflare API returned status \(http.statusCode).")
        }
        return try JSONDecoder().decode(AccountsResponse.self, from: data).result.map(\.id)
    }
}

private struct AccountsResponse: Decodable {
    struct Account: Decodable { let id: String }
    let result: [Account]
}

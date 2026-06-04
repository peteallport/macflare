//
//  CloudflareAuthManager.swift
//  macflare
//
//  Coordinates the full Cloudflare OAuth lifecycle.
//

import Foundation
import Observation

/// Coordinates the full Cloudflare OAuth lifecycle: launching the consent flow,
/// exchanging the authorization code (PKCE), persisting tokens to the Keychain,
/// refreshing them, and signing out.
@MainActor
@Observable
final class CloudflareAuthManager {
    private(set) var state: AuthState = .signedOut

    @ObservationIgnored private let authorizer: OAuthRedirectAuthorizing
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private var token: AuthToken?

    init(
        authorizer: OAuthRedirectAuthorizing? = nil,
        keychain: KeychainStore = KeychainStore(),
        urlSession: URLSession = .shared
    ) {
        self.authorizer = authorizer ?? WebAuthenticationSessionAuthorizer()
        self.keychain = keychain
        self.urlSession = urlSession
    }

    /// Restores any previously persisted session. Call once at launch.
    func restore() {
        if let stored = try? keychain.load() {
            token = stored
            state = .signedIn
        }
    }

    /// Builds an API client whose bearer token is always valid (refreshed first).
    func makeAPIClient() -> CloudflareAPIClient {
        CloudflareAPIClient(
            tokenProvider: { [weak self] in
                guard let self else { throw OAuthError.notConfigured }
                return try await self.validAccessToken()
            },
            session: urlSession
        )
    }

    /// Runs the Authorization Code + PKCE flow end to end.
    func signIn() async {
        guard CloudflareOAuthConfig.isConfigured else {
            state = .failed(OAuthError.notConfigured.localizedDescription)
            return
        }
        state = .authenticating
        do {
            let pkce = PKCE()
            let expectedState = PKCE.makeState()
            let authURL = makeAuthorizationURL(pkce: pkce, state: expectedState)

            let callback = try await authorizer.authorize(
                url: authURL,
                callbackScheme: CloudflareOAuthConfig.callbackURLScheme
            )
            let code = try authorizationCode(from: callback, expectedState: expectedState)
            let newToken = try await exchange(code: code, verifier: pkce.codeVerifier)

            try keychain.save(newToken)
            token = newToken
            state = .signedIn
        } catch {
            let message = (error as? OAuthError)?.localizedDescription ?? error.localizedDescription
            state = .failed(message)
        }
    }

    /// Clears the session and persisted token.
    func signOut() {
        try? keychain.delete()
        token = nil
        state = .signedOut
    }

    // MARK: - Token handling

    /// Returns a non-expired access token, refreshing it if necessary.
    private func validAccessToken() async throws -> String {
        guard let current = token else { throw OAuthError.notConfigured }
        if current.isExpired(), let refreshToken = current.refreshToken {
            let refreshed = try await refresh(using: refreshToken)
            try keychain.save(refreshed)
            token = refreshed
            return refreshed.accessToken
        }
        return current.accessToken
    }

    // MARK: - Request building

    private func makeAuthorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(
            url: CloudflareOAuthConfig.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: CloudflareOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: CloudflareOAuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: CloudflareOAuthConfig.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        return components.url!
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw OAuthError.missingAuthorizationCode
        }
        if let serverError = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value
            throw OAuthError.server(description ?? serverError)
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
            throw OAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OAuthError.missingAuthorizationCode
        }
        return code
    }

    private func exchange(code: String, verifier: String) async throws -> AuthToken {
        try await postToken(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": CloudflareOAuthConfig.redirectURI,
            "client_id": CloudflareOAuthConfig.clientID,
            "code_verifier": verifier,
        ])
    }

    private func refresh(using refreshToken: String) async throws -> AuthToken {
        let refreshed = try await postToken(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": CloudflareOAuthConfig.clientID,
        ])
        // Cloudflare may omit a rotated refresh token; keep the existing one.
        guard refreshed.refreshToken == nil else { return refreshed }
        return AuthToken(
            accessToken: refreshed.accessToken,
            refreshToken: refreshToken,
            tokenType: refreshed.tokenType,
            scope: refreshed.scope,
            expiresAt: refreshed.expiresAt
        )
    }

    private func postToken(parameters: [String: String]) async throws -> AuthToken {
        var request = URLRequest(url: CloudflareOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncode(parameters).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.server("Invalid response from Cloudflare token endpoint.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorMessage(from: data)
                ?? "Token request failed (status \(http.statusCode))."
            throw OAuthError.server(message)
        }
        return try JSONDecoder().decode(AuthToken.self, from: data)
    }

    private static func formURLEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    private static func errorMessage(from data: Data) -> String? {
        struct TokenError: Decodable {
            let error: String?
            let errorDescription: String?
            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
        }
        guard let decoded = try? JSONDecoder().decode(TokenError.self, from: data) else { return nil }
        return decoded.errorDescription ?? decoded.error
    }
}

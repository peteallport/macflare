//
//  OAuthTests.swift
//  macflareTests
//
//  Tests for the Cloudflare OAuth (public client + PKCE) building blocks.
//

import Foundation
import Testing
@testable import macflare

@MainActor
struct OAuthTests {

    @Test func selfManagedClientUsesCurrentScopesAndLoopbackRedirect() {
        let config = CloudflareOAuthConfig(clientID: "test-client")
        #expect(config.scopes == ["account-settings.read", "offline_access"])
        #expect(config.redirectURI == "http://127.0.0.1:8976/oauth/callback")
        #expect(config.isConfigured)
        #expect(!CloudflareOAuthConfig(clientID: "").isConfigured)
        #expect(!CloudflareOAuthConfig(clientID: "$(CLOUDFLARE_CLIENT_ID)").isConfigured)
    }

    @Test func loopbackCallbackAcceptsMatchingHostPathAndState() throws {
        let callback = try LoopbackOAuthCallback.parse(
            request: "GET /oauth/callback?code=test-code&state=expected HTTP/1.1\r\nHost: 127.0.0.1:8976\r\n\r\n",
            redirectURI: "http://127.0.0.1:8976/oauth/callback",
            expectedState: "expected"
        )
        #expect(callback.absoluteString == "http://127.0.0.1:8976/oauth/callback?code=test-code&state=expected")
    }

    @Test(arguments: [
        "GET /oauth/callback?code=test&state=wrong HTTP/1.1\r\nHost: 127.0.0.1:8976\r\n\r\n",
        "GET /oauth/callback?code=test&state=expected&state=expected HTTP/1.1\r\nHost: 127.0.0.1:8976\r\n\r\n",
        "GET /unexpected?code=test&state=expected HTTP/1.1\r\nHost: 127.0.0.1:8976\r\n\r\n",
        "GET /oauth/callback?code=test&state=expected HTTP/1.1\r\nHost: example.test\r\n\r\n",
        "GET /oauth/callback?code=test&state=expected HTTP/1.1\r\n\r\n",
        "GET /oauth/callback?code=test&state=expected HTTP/1.1\r\nHost: 127.0.0.1:8976\r\nHost: 127.0.0.1:8976\r\n\r\n",
        "POST /oauth/callback?code=test&state=expected HTTP/1.1\r\nHost: 127.0.0.1:8976\r\n\r\n",
        "GET http://example.test/oauth/callback?code=test&state=expected HTTP/1.1\r\nHost: 127.0.0.1:8976\r\n\r\n",
    ])
    func loopbackCallbackRejectsUnmatchedOrAmbiguousRequests(request: String) {
        #expect(throws: (any Error).self) {
            try LoopbackOAuthCallback.parse(
                request: request,
                redirectURI: "http://127.0.0.1:8976/oauth/callback",
                expectedState: "expected"
            )
        }
    }

    // MARK: - PKCE

    /// Known-answer test from RFC 7636 Appendix B.
    @Test func pkceChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCE.makeChallenge(for: verifier)
        #expect(challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func pkceGeneratesURLSafeChallenge() {
        let pkce = PKCE()
        #expect(!pkce.codeVerifier.isEmpty)
        #expect(pkce.method == "S256")
        #expect(!pkce.codeChallenge.contains("="))
        #expect(!pkce.codeChallenge.contains("+"))
        #expect(!pkce.codeChallenge.contains("/"))
        // The challenge must be reproducible from its verifier.
        #expect(PKCE.makeChallenge(for: pkce.codeVerifier) == pkce.codeChallenge)
    }

    @Test func pkceVerifiersAreUnique() {
        let first = PKCE()
        let second = PKCE()
        #expect(first.codeVerifier != second.codeVerifier)
    }

    // MARK: - AuthToken

    @Test func authTokenDecodesExpiresIntoAbsoluteDate() throws {
        let json = Data("""
        {"access_token":"abc","refresh_token":"def","token_type":"bearer","scope":"account-settings.read","expires_in":3600}
        """.utf8)
        let token = try JSONDecoder().decode(AuthToken.self, from: json)
        #expect(token.accessToken == "abc")
        #expect(token.refreshToken == "def")
        #expect(token.tokenType == "bearer")
        #expect(token.expiresAt != nil)
        #expect(!token.isExpired())
    }

    @Test func authTokenDefaultsTokenTypeWhenMissing() throws {
        let json = Data(#"{"access_token":"abc"}"#.utf8)
        let token = try JSONDecoder().decode(AuthToken.self, from: json)
        #expect(token.tokenType == "Bearer")
        #expect(token.refreshToken == nil)
        #expect(token.expiresAt == nil)
        // An OAuth token with unknown expiry must be refreshed before use.
        #expect(token.isExpired())
    }

    @Test func authTokenRoundTripsThroughCoding() throws {
        let original = AuthToken(
            accessToken: "a",
            refreshToken: "r",
            tokenType: "Bearer",
            scope: "account-settings.read",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AuthToken.self, from: data)
        #expect(decoded == original)
    }

    @Test func expiredTokenIsDetected() {
        let token = AuthToken(
            accessToken: "a",
            refreshToken: nil,
            tokenType: "Bearer",
            scope: nil,
            expiresAt: Date().addingTimeInterval(-10)
        )
        #expect(token.isExpired())
    }

    // MARK: - Keychain

    @Test func keychainStoreRoundTripsToken() throws {
        // Use a unique account so the test never collides with a real session.
        let store = KeychainStore(service: "com.macflare.tests", account: UUID().uuidString)
        defer { try? store.delete() }

        let token = AuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            scope: "account-settings.read",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try store.save(token)

        let loaded = try store.load()
        #expect(loaded == token)

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test func keychainClientIsolationPreservesProductionAndLegacySessions() throws {
        let service = "com.macflare.tests.\(UUID().uuidString)"
        let development = KeychainStore(clientID: "test-development", service: service)
        let production = KeychainStore(clientID: "test-production", service: service)
        let legacy = KeychainStore(service: service)
        defer {
            try? development.delete()
            try? production.delete()
            try? legacy.delete()
        }

        func token(_ name: String) -> AuthToken {
            AuthToken(accessToken: "\(name)-access", refreshToken: "\(name)-refresh",
                      tokenType: "Bearer", scope: "account-settings.read offline_access",
                      expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
        }
        let legacyToken = token("legacy")
        let developmentToken = token("development")
        let productionToken = token("production")
        try legacy.save(legacyToken)

        // A registration must never adopt an older item whose client is unknown.
        #expect(try development.load() == nil)
        #expect(try production.load() == nil)
        try development.save(developmentToken)
        try production.save(productionToken)
        #expect(try development.load() == developmentToken)
        #expect(try production.load() == productionToken)
        #expect(try legacy.load() == legacyToken)

        try development.delete()
        #expect(try development.load() == nil)
        #expect(try production.load() == productionToken)
        #expect(try legacy.load() == legacyToken)
    }
}

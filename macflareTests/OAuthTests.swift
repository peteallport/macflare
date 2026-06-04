//
//  OAuthTests.swift
//  macflareTests
//
//  Tests for the Cloudflare OAuth (public client + PKCE) building blocks.
//

import Foundation
import Testing
@testable import macflare

struct OAuthTests {

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
        #expect(PKCE().codeVerifier != PKCE().codeVerifier)
    }

    // MARK: - AuthToken

    @Test func authTokenDecodesExpiresIntoAbsoluteDate() throws {
        let json = Data("""
        {"access_token":"abc","refresh_token":"def","token_type":"bearer","scope":"account:read","expires_in":3600}
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
        // A token with no expiry is treated as non-expiring.
        #expect(!token.isExpired())
    }

    @Test func authTokenRoundTripsThroughCoding() throws {
        let original = AuthToken(
            accessToken: "a",
            refreshToken: "r",
            tokenType: "Bearer",
            scope: "account:read",
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
            scope: "account:read",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try store.save(token)

        let loaded = try store.load()
        #expect(loaded == token)

        try store.delete()
        #expect(try store.load() == nil)
    }
}

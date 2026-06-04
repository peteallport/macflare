//
//  PKCE.swift
//  macflare
//
//  Proof Key for Code Exchange (RFC 7636) helpers for the OAuth flow.
//

import CryptoKit
import Foundation

/// PKCE parameters (RFC 7636) for a single OAuth authorization.
///
/// Public clients cannot hold a client secret, so PKCE binds the authorization
/// request to the token exchange: we send a hashed ``codeChallenge`` up front and
/// prove possession of the original ``codeVerifier`` when redeeming the code.
struct PKCE: Equatable {
    let codeVerifier: String
    let codeChallenge: String
    let method = "S256"

    init() {
        let verifier = PKCE.makeCodeVerifier()
        self.codeVerifier = verifier
        self.codeChallenge = PKCE.makeChallenge(for: verifier)
    }

    /// Generates a high-entropy, URL-safe code verifier (RFC 7636 §4.1).
    static func makeCodeVerifier() -> String {
        randomBase64URLString(byteCount: 32)
    }

    /// Computes the S256 challenge: BASE64URL(SHA256(ASCII(verifier))).
    static func makeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    /// A random, URL-safe `state` value to defend against CSRF on the callback.
    static func makeState() -> String {
        randomBase64URLString(byteCount: 16)
    }

    private static func randomBase64URLString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    /// Base64URL encoding without padding (RFC 4648 §5), as required by PKCE.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

//
//  OAuthWebSession.swift
//  macflare
//
//  Browser round-trip that returns the OAuth redirect URL.
//

import AuthenticationServices
import Foundation

#if os(macOS)
import AppKit
#endif

/// Errors surfaced by the OAuth flow.
enum OAuthError: Error, LocalizedError, Equatable {
    case notConfigured
    case userCancelled
    case missingCallbackURL
    case stateMismatch
    case missingAuthorizationCode
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloudflare OAuth client is not configured."
        case .userCancelled:
            return "Sign in was cancelled."
        case .missingCallbackURL:
            return "No callback was received from Cloudflare."
        case .stateMismatch:
            return "The sign-in response failed a security check. Please try again."
        case .missingAuthorizationCode:
            return "Cloudflare did not return an authorization code."
        case .server(let message):
            return message
        }
    }
}

/// Abstraction over the browser round-trip that returns the OAuth redirect URL.
///
/// Keeping this behind a protocol lets the redirect mechanism — custom-scheme
/// `ASWebAuthenticationSession` today, a loopback listener if Cloudflare's public
/// client registration ever requires it — change without touching flow logic.
@MainActor
protocol OAuthRedirectAuthorizing {
    /// Opens `url`, waits for the redirect to the registered callback scheme, and
    /// returns the full callback URL (including `code` and `state`).
    func authorize(url: URL, callbackScheme: String) async throws -> URL
}

/// `ASWebAuthenticationSession`-backed implementation. Presents Apple's secure,
/// ephemeral auth web view and captures the custom-scheme redirect.
@MainActor
final class WebAuthenticationSessionAuthorizer: NSObject, OAuthRedirectAuthorizing {
    /// Held for the lifetime of the flow; `ASWebAuthenticationSession` is
    /// cancelled if its strong reference is dropped before completion.
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthError.missingCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                self.session = nil
                continuation.resume(throwing: OAuthError.missingCallbackURL)
            }
        }
    }
}

extension WebAuthenticationSessionAuthorizer: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

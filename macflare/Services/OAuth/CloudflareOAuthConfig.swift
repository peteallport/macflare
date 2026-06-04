//
//  CloudflareOAuthConfig.swift
//  macflare
//
//  Static configuration for Cloudflare's public OAuth client flow.
//

import Foundation

/// Configuration for authenticating with Cloudflare as a *public* OAuth client.
///
/// As of Cloudflare's 2026-06-03 "public OAuth clients" release, native apps can
/// use the OAuth 2.0 Authorization Code flow with PKCE and **no client secret**,
/// which is exactly what a distributed desktop app like MacFlare needs.
enum CloudflareOAuthConfig {
    /// The client ID issued when registering a public OAuth client in the
    /// Cloudflare dashboard. Public clients have no secret.
    ///
    /// - Important: Populate this with the real client ID before shipping. It is
    ///   intentionally left empty so an unconfigured build fails loudly (via
    ///   ``isConfigured``) rather than starting a broken sign-in.
    static let clientID = ""

    /// Endpoint the user is sent to in order to grant consent.
    static let authorizationEndpoint = URL(string: "https://dash.cloudflare.com/oauth2/auth")!

    /// Endpoint used to exchange the authorization code (and later refresh
    /// tokens) for access tokens.
    static let tokenEndpoint = URL(string: "https://dash.cloudflare.com/oauth2/token")!

    /// Base URL for the Cloudflare REST API, used once authenticated.
    static let apiBaseURL = URL(string: "https://api.cloudflare.com/client/v4")!

    /// Custom URL scheme registered in `Info.plist` for the OAuth redirect.
    static let callbackURLScheme = "macflare"

    /// Redirect URI registered with the OAuth client. The custom scheme lets
    /// `ASWebAuthenticationSession` intercept the callback automatically.
    static let redirectURI = "\(callbackURLScheme)://oauth-callback"

    /// Requested scopes. `offline_access` is required to receive a refresh token.
    static let scopes = [
        "account:read",
        "user:read",
        "zone:read",
        "offline_access",
    ]

    /// Space-delimited scope string for the authorization request.
    static var scopeString: String { scopes.joined(separator: " ") }

    /// Whether a usable client ID has been configured.
    static var isConfigured: Bool { !clientID.isEmpty }
}

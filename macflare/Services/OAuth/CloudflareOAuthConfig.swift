//
//  CloudflareOAuthConfig.swift
//  macflare
//
//  Configuration for Cloudflare's public OAuth client flow.
//

import Foundation

/// Public PKCE client configuration. A client ID identifies the app and is not a secret.
struct CloudflareOAuthConfig: Sendable {
    let clientID: String
    var authorizationEndpoint = URL(string: "https://dash.cloudflare.com/oauth2/auth")!
    var tokenEndpoint = URL(string: "https://dash.cloudflare.com/oauth2/token")!
    var revocationEndpoint = URL(string: "https://dash.cloudflare.com/oauth2/revoke")!
    var apiBaseURL = URL(string: "https://api.cloudflare.com/client/v4")!
    var redirectURI = "http://127.0.0.1:8976/oauth/callback"

    /// Self-managed clients use dot-delimited scopes; Wrangler's legacy colon scopes
    /// are not accepted. Request only account listing and refresh-token access.
    var scopes = ["account-settings.read", "offline_access"]

    var scopeString: String { scopes.joined(separator: " ") }
    var isConfigured: Bool { !clientID.isEmpty && !clientID.hasPrefix("$(") }

    /// Supplied with CLOUDFLARE_CLIENT_ID at build time; no credentials in source.
    static let live: CloudflareOAuthConfig = {
        let value = Bundle.main.object(forInfoDictionaryKey: "CloudflareClientID") as? String ?? ""
        return CloudflareOAuthConfig(clientID: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }()
}

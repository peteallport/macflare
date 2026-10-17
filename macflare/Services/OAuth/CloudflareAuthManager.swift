//
//  CloudflareAuthManager.swift
//  macflare
//
//  Coordinates the full Cloudflare OAuth lifecycle.
//

import Foundation
import Observation

/// Observable session and account state, with injectable boundaries for offline
/// lifecycle tests. Every asynchronous result belongs to one session generation.
@MainActor
@Observable
final class CloudflareAuthManager {
    private(set) var state: AuthState = .signedOut
    private(set) var accounts: [CloudflareAccount] = []
    private(set) var isLoadingAccounts = false
    private(set) var accountError: String?
    private(set) var sessionNotice: String?
    private(set) var canRetrySignOut = false

    @ObservationIgnored private let authorizer: any OAuthRedirectAuthorizing
    @ObservationIgnored private let keychain: any AuthTokenStoring
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let configuration: CloudflareOAuthConfig
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var token: AuthToken?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<AuthToken, Error>?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var accountLoadID: UUID?
    @ObservationIgnored private var shouldRetryRestore = false
    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored private var needsTokenPersistence = false

    init(
        authorizer: (any OAuthRedirectAuthorizing)? = nil,
        keychain: (any AuthTokenStoring)? = nil,
        urlSession: URLSession = .shared,
        configuration: CloudflareOAuthConfig = .live,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.authorizer = authorizer ?? WebAuthenticationSessionAuthorizer()
        self.keychain = keychain ?? KeychainStore(clientID: configuration.clientID)
        self.urlSession = urlSession
        self.configuration = configuration
        self.now = now
    }

    var canRetrySession: Bool {
        !state.isAuthenticating && !state.isSignedIn && (token != nil || shouldRetryRestore)
    }

    /// A saved token alone never establishes a session. Check expiration and
    /// refresh it before loading the accounts that the user can actually access.
    func restore() async {
        guard !didAttemptRestore else { return }
        await restoreSavedSession()
    }

    private func restoreSavedSession() async {
        guard !state.isAuthenticating, !state.isSignedIn else { return }
        didAttemptRestore = true
        state = .restoring
        sessionNotice = nil
        shouldRetryRestore = false
        do {
            guard let stored = try keychain.load() else {
                state = .signedOut
                return
            }
            token = stored
            await loadAccounts()
        } catch {
            shouldRetryRestore = true
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        guard !state.isAuthenticating else { return }
        if token == nil {
            await restoreSavedSession()
        } else {
            state = .restoring
            await loadAccounts()
        }
    }

    /// API clients cannot silently change identity after a subsequent sign-in.
    func makeAPIClient() -> CloudflareAPIClient {
        let expectedGeneration = generation
        return CloudflareAPIClient(
            tokenProvider: { [weak self] in
                guard let self else { throw OAuthError.sessionExpired }
                try self.checkGeneration(expectedGeneration)
                return try await self.validAccessToken()
            },
            session: urlSession,
            baseURL: configuration.apiBaseURL,
            refreshToken: { [weak self] rejectedToken in
                guard let self else { throw OAuthError.sessionExpired }
                try self.checkGeneration(expectedGeneration)
                // Another request may already have rotated this rejected token.
                if self.token?.accessToken != rejectedToken {
                    return try await self.validAccessToken()
                }
                return try await self.validAccessToken(forceRefresh: true)
            },
            invalidateToken: { [weak self] rejectedToken in
                guard let self, self.generation == expectedGeneration,
                      self.token?.accessToken == rejectedToken else { return }
                self.expireSession()
            }
        )
    }

    func signIn() async {
        guard !state.isAuthenticating, !state.isSignedIn else { return }
        guard configuration.isConfigured else {
            state = .failed(OAuthError.notConfigured.localizedDescription)
            return
        }
        beginNewGeneration()
        let expectedGeneration = generation
        state = .authenticating
        token = nil
        needsTokenPersistence = false
        didAttemptRestore = true
        sessionNotice = nil
        shouldRetryRestore = false
        do {
            let pkce = PKCE()
            let expectedState = PKCE.makeState()
            let authURL = makeAuthorizationURL(pkce: pkce, state: expectedState)
            let callback = try await authorizer.authorize(
                url: authURL,
                redirectURI: configuration.redirectURI
            )
            try checkGeneration(expectedGeneration)
            let code = try authorizationCode(from: callback, expectedState: expectedState)
            let newToken = try await exchange(code: code, verifier: pkce.codeVerifier)
            try checkGeneration(expectedGeneration)
            try keychain.save(newToken)
            canRetrySignOut = false
            token = newToken
            await loadAccounts()
        } catch {
            guard generation == expectedGeneration else { return }
            if error is CancellationError || error as? OAuthError == .userCancelled {
                state = .signedOut
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Local sign-out takes effect before awaiting best-effort remote revocation.
    /// Failed deletion/revocation stays visible without restoring local access.
    func signOut() async {
        let refreshToken = token?.refreshToken
        beginNewGeneration()
        let expectedGeneration = generation
        token = nil
        needsTokenPersistence = false
        didAttemptRestore = true
        accounts = []
        accountError = nil
        sessionNotice = nil
        shouldRetryRestore = false
        state = .signedOut
        do {
            try keychain.delete()
            canRetrySignOut = false
        } catch {
            canRetrySignOut = true
            sessionNotice = "Signed out here, but the saved session could not be removed from Keychain. \(error.localizedDescription)"
        }
        guard let refreshToken, !refreshToken.isEmpty else { return }
        do {
            var request = formRequest(url: configuration.revocationEndpoint, parameters: [
                "client_id": configuration.clientID,
                "token": refreshToken,
                "token_type_hint": "refresh_token",
            ])
            request.timeoutInterval = 15
            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw OAuthError.server("Cloudflare did not confirm session revocation.")
            }
        } catch {
            guard generation == expectedGeneration else { return }
            let message = "Signed out of MacFlare. Cloudflare session revocation could not be confirmed; you can revoke MacFlare in Cloudflare's Authorized Apps settings."
            sessionNotice = [sessionNotice, message].compactMap { $0 }.joined(separator: " ")
        }
    }

    /// Refreshes the account list and exposes loading/error state to the UI.
    func loadAccounts(forceRefresh: Bool = false) async {
        guard token != nil, accountLoadID == nil else { return }
        let expectedGeneration = generation
        let loadID = UUID()
        accountLoadID = loadID
        isLoadingAccounts = true
        accountError = nil
        defer {
            if accountLoadID == loadID {
                accountLoadID = nil
                isLoadingAccounts = false
            }
        }
        do {
            _ = try await validAccessToken(forceRefresh: forceRefresh)
            try checkGeneration(expectedGeneration)
            let loaded = try await makeAPIClient().loadAccounts()
            try checkGeneration(expectedGeneration)
            accounts = loaded
            state = .signedIn
        } catch {
            guard generation == expectedGeneration else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = .failed("Cloudflare account loading was cancelled. Retry to continue.")
                return
            }
            accountError = error.localizedDescription
            if let token, !token.isExpired(now: now()) {
                // Network and permission failures are retryable account errors,
                // not proof that the underlying session has been revoked.
                state = .signedIn
            } else if token != nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Token handling

    /// Concurrent callers share one refresh, including refresh-token rotation.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        guard let current = token else { throw OAuthError.sessionExpired }
        if !forceRefresh && !current.isExpired(now: now()) {
            if needsTokenPersistence { persistRefreshedToken(current) }
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            expireSession()
            throw OAuthError.sessionExpired
        }
        guard configuration.isConfigured else { throw OAuthError.notConfigured }
        let expectedGeneration = generation
        let id = UUID()
        refreshID = id
        let task = Task { @MainActor [self] () throws -> AuthToken in
            defer {
                if refreshID == id {
                    refreshTask = nil
                    refreshID = nil
                }
            }
            do {
                let refreshed = try await refresh(using: refreshToken)
                try checkGeneration(expectedGeneration)
                // Keep rotated credentials in memory if Keychain is temporarily
                // unavailable; reverting to the consumed token would strand retry.
                token = refreshed
                persistRefreshedToken(refreshed)
                return refreshed
            } catch {
                guard generation == expectedGeneration else { throw CancellationError() }
                if error as? OAuthError == .invalidGrant {
                    expireSession()
                }
                throw error
            }
        }
        refreshTask = task
        return try await task.value.accessToken
    }

    private func persistRefreshedToken(_ refreshed: AuthToken) {
        do {
            try keychain.save(refreshed)
            if needsTokenPersistence { sessionNotice = nil }
            needsTokenPersistence = false
        } catch {
            needsTokenPersistence = true
            sessionNotice = "Your refreshed session could not be saved. Keep MacFlare open and refresh accounts to retry before relaunching. \(error.localizedDescription)"
        }
    }

    private func expireSession() {
        beginNewGeneration()
        token = nil
        needsTokenPersistence = false
        didAttemptRestore = true
        accounts = []
        accountError = nil
        shouldRetryRestore = false
        state = .expired(OAuthError.sessionExpired.localizedDescription)
        sessionNotice = nil
        do {
            try keychain.delete()
            canRetrySignOut = false
        } catch {
            canRetrySignOut = true
            sessionNotice = "The expired session could not be removed from Keychain. \(error.localizedDescription)"
        }
    }

    private func beginNewGeneration() {
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        authorizer.cancel()
        accountLoadID = nil
        isLoadingAccounts = false
        accounts = []
        accountError = nil
    }

    private func checkGeneration(_ expected: Int) throws {
        guard generation == expected else { throw CancellationError() }
        try Task.checkCancellation()
    }

    // MARK: - Requests and callback validation

    private func makeAuthorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: configuration.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
        ]
        return components.url!
    }

    private func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let expected = URLComponents(string: configuration.redirectURI),
              components.scheme?.lowercased() == expected.scheme?.lowercased(),
              components.host?.lowercased() == expected.host?.lowercased(),
              components.port == expected.port,
              components.percentEncodedPath == expected.percentEncodedPath,
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw OAuthError.invalidCallbackURL
        }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states[0].value == expectedState else { throw OAuthError.stateMismatch }
        let errors = items.filter { $0.name == "error" }
        let codes = items.filter { $0.name == "code" }
        if !errors.isEmpty {
            guard errors.count == 1, codes.isEmpty else { throw OAuthError.invalidCallbackURL }
            if errors[0].value == "access_denied" { throw OAuthError.userCancelled }
            // Avoid reflecting arbitrary callback text into the app or logs.
            throw OAuthError.server("Cloudflare could not complete authorization. Please try again.")
        }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else {
            throw OAuthError.missingAuthorizationCode
        }
        return code
    }

    private func exchange(code: String, verifier: String) async throws -> AuthToken {
        try await postToken(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "client_id": configuration.clientID,
            "code_verifier": verifier,
        ])
    }

    private func refresh(using refreshToken: String) async throws -> AuthToken {
        let refreshed = try await postToken(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": configuration.clientID,
        ])
        return AuthToken(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? refreshToken,
            tokenType: refreshed.tokenType,
            scope: refreshed.scope,
            expiresAt: refreshed.expiresAt
        )
    }

    private func postToken(parameters: [String: String]) async throws -> AuthToken {
        let request = formRequest(url: configuration.tokenEndpoint, parameters: parameters)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.invalidTokenResponse }
        guard (200..<300).contains(http.statusCode) else {
            struct TokenError: Decodable { let error: String? }
            let code = (try? JSONDecoder().decode(TokenError.self, from: data))?.error
            if code == "invalid_grant" { throw OAuthError.invalidGrant }
            if code == "invalid_client" {
                throw OAuthError.server("Cloudflare rejected MacFlare's OAuth client configuration. Check the registered client ID and redirect URI.")
            }
            throw OAuthError.server("Cloudflare could not refresh or create your session (status \(http.statusCode)). Please retry.")
        }
        let decoder = JSONDecoder()
        decoder.userInfo[.authTokenReferenceDate] = now()
        let decoded: AuthToken
        do {
            decoded = try decoder.decode(AuthToken.self, from: data)
        } catch {
            throw OAuthError.invalidTokenResponse
        }
        guard !decoded.accessToken.isEmpty, decoded.tokenType.lowercased() == "bearer",
              !decoded.isExpired(now: now(), leeway: 0) else { throw OAuthError.invalidTokenResponse }
        return decoded
    }

    private func formRequest(url: URL, parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = parameters.sorted(by: { $0.key < $1.key }).map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&").data(using: .utf8)
        return request
    }
}

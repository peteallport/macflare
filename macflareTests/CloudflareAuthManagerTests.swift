//
//  CloudflareAuthManagerTests.swift
//  macflareTests
//
//  Created by Peter C. Allport on 10/16/26.
//

import Foundation
import Testing
@testable import macflare

/// This suite exercises actual URLSession request building and response handling
/// offline. Serialization isolates the URLProtocol registration; the credential
/// store and clock are per-test fakes.
@Suite(.serialized)
@MainActor
struct CloudflareAuthManagerTests {
    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeFixture(
        token: AuthToken? = nil,
        responses: [OAuthStubResponse] = [],
        authorizer: OAuthTestAuthorizer? = nil
    ) -> OAuthFixture {
        let authorizer = authorizer ?? OAuthTestAuthorizer()
        let server = OAuthTestServer(responses: responses)
        OAuthStubProtocol.server = server
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [OAuthStubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let store = OAuthMemoryStore(token: token)
        let clock = OAuthTestClock(now: Self.instant)
        let configuration = CloudflareOAuthConfig(
            clientID: "test-client",
            authorizationEndpoint: URL(string: "https://oauth.example.test/auth")!,
            tokenEndpoint: URL(string: "https://oauth.example.test/token")!,
            revocationEndpoint: URL(string: "https://oauth.example.test/revoke")!,
            apiBaseURL: URL(string: "https://api.example.test/client/v4")!,
            redirectURI: "macflare://oauth-callback",
            scopes: ["account.read", "offline_access"]
        )
        let manager = CloudflareAuthManager(
            authorizer: authorizer,
            keychain: store,
            urlSession: session,
            configuration: configuration,
            now: { clock.now }
        )
        return OAuthFixture(manager: manager, store: store, server: server,
                            authorizer: authorizer, clock: clock, session: session)
    }

    private func token(
        access: String = "old-access",
        refresh: String? = "old-refresh",
        expired: Bool = false
    ) -> AuthToken {
        AuthToken(accessToken: access, refreshToken: refresh, tokenType: "Bearer",
                  scope: "account.read offline_access",
                  expiresAt: Self.instant.addingTimeInterval(expired ? -1 : 3_600))
    }

    @Test func signInExchangesPKCECodeAndLoadsAccounts() async throws {
        let fixture = makeFixture(responses: [.refreshed, .accounts])
        await fixture.manager.signIn()

        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.map(\.id) == ["account-one", "account-two"])
        #expect(fixture.store.token?.accessToken == "new-access")
        #expect(fixture.store.token?.expiresAt == Self.instant.addingTimeInterval(3_600))
        let requests = await fixture.server.requests
        #expect(requests.count == 2)
        let exchange = try #require(requests.first)
        #expect(exchange.httpMethod == "POST")
        #expect(exchange.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let form = try decodeForm(exchange)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "code+with&reserved=characters")
        #expect(form["client_id"] == "test-client")
        #expect(form["redirect_uri"] == "macflare://oauth-callback")
        #expect(form["client_secret"] == nil)

        let authURL = try #require(fixture.authorizer.authorizationURL)
        let query = try #require(URLComponents(url: authURL, resolvingAgainstBaseURL: false)?.queryItems)
        let verifier = try #require(form["code_verifier"])
        #expect(query.first { $0.name == "code_challenge" }?.value == PKCE.makeChallenge(for: verifier))
        #expect(query.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(query.first { $0.name == "response_type" }?.value == "code")
        #expect(query.first { $0.name == "scope" }?.value == "account.read offline_access")
        #expect(fixture.authorizer.callbackScheme == "macflare")
        #expect(requests.last?.url?.path == "/client/v4/accounts")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test(arguments: [OAuthTestAuthorizer.Callback.wrongState, .wrongRedirect, .missingCode, .duplicateState])
    private func rejectsInvalidCallbackBeforeTokenExchange(callback: OAuthTestAuthorizer.Callback) async {
        let authorizer = OAuthTestAuthorizer()
        authorizer.callback = callback
        let fixture = makeFixture(authorizer: authorizer)
        await fixture.manager.signIn()

        #expect(!fixture.manager.state.isSignedIn)
        #expect(fixture.manager.state.failureMessage != nil)
        #expect(fixture.store.token == nil)
        #expect(await fixture.server.requests.isEmpty)
    }

    @Test func cancellingSignInLeavesNoSession() async {
        let authorizer = OAuthTestAuthorizer()
        authorizer.callback = .cancelled
        let fixture = makeFixture(authorizer: authorizer)
        await fixture.manager.signIn()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.store.token == nil)
        #expect(await fixture.server.requests.isEmpty)
    }

    @Test func restoresValidSessionAndLoadsAccountsWithoutRefresh() async {
        let fixture = makeFixture(token: token(), responses: [.accounts])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.count == 2)
        #expect(fixture.store.saveCount == 0)
        let requests = await fixture.server.requests
        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    }

    @Test func automaticRestoreReadsSavedSessionOnlyOncePerAppLifetime() async {
        let fixture = makeFixture()
        await fixture.manager.restore()
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.store.loadCount == 1)
        #expect(await fixture.server.requests.isEmpty)
    }

    @Test func expiredRestoreRefreshesBeforeLoadingAccounts() async throws {
        let fixture = makeFixture(token: token(expired: true), responses: [.refreshed, .accounts])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.store.token?.refreshToken == "new-refresh")
        #expect(fixture.manager.accounts.count == 2)
        let requests = await fixture.server.requests
        #expect(requests.count == 2)
        let form = try decodeForm(try #require(requests.first))
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["refresh_token"] == "old-refresh")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test func explicitRefreshActionRotatesUsableTokenAndReloadsAccounts() async throws {
        let fixture = makeFixture(token: token(), responses: [.accounts, .refreshed, .accounts])
        await fixture.manager.restore()
        await fixture.manager.loadAccounts(forceRefresh: true)

        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.count == 2)
        #expect(!fixture.manager.isLoadingAccounts)
        #expect(fixture.manager.accountError == nil)
        #expect(fixture.store.token?.refreshToken == "new-refresh")
        let requests = await fixture.server.requests
        #expect(requests.count == 3)
        let refreshRequest = try #require(requests.first { $0.url?.path == "/token" })
        let form = try decodeForm(refreshRequest)
        #expect(form["grant_type"] == "refresh_token")
        #expect(form["refresh_token"] == "old-refresh")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test func refreshRetainsPreviousRefreshTokenWhenResponseOmitsRotation() async {
        let response = OAuthStubResponse(status: 200, body: #"{"access_token":"new-access","expires_in":3600}"#)
        let fixture = makeFixture(token: token(expired: true), responses: [response, .accounts])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.store.token?.refreshToken == "old-refresh")
    }

    @Test func expiredTokenWithoutRefreshCannotReachAccounts() async {
        let fixture = makeFixture(token: token(refresh: nil, expired: true))
        await fixture.manager.restore()
        #expect(fixture.manager.state == .expired(OAuthError.sessionExpired.localizedDescription))
        #expect(!fixture.manager.canRetrySession)
        #expect(fixture.store.token == nil)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(await fixture.server.requests.isEmpty)
    }

    @Test func invalidGrantExpiresAndDeletesStoredSession() async {
        let fixture = makeFixture(token: token(expired: true), responses: [.invalidGrant])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .expired(OAuthError.sessionExpired.localizedDescription))
        #expect(!fixture.manager.canRetrySession)
        #expect(fixture.store.token == nil)
        #expect(fixture.store.deleteCount == 1)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(await fixture.server.requests.count == 1)
    }

    @Test func transientRefreshFailurePreservesCredentialsAndAllowsRetry() async {
        let offline = OAuthStubResponse(status: 0, body: "", error: URLError(.notConnectedToInternet))
        let original = token(expired: true)
        let fixture = makeFixture(token: original, responses: [offline, .refreshed, .accounts])
        await fixture.manager.restore()
        #expect(!fixture.manager.state.isSignedIn)
        #expect(fixture.manager.canRetrySession)
        #expect(fixture.store.token == original)
        #expect(fixture.store.deleteCount == 0)

        await fixture.manager.retry()
        #expect(fixture.manager.state == .signedIn)
        #expect(!fixture.manager.canRetrySession)
        #expect(fixture.manager.accounts.count == 2)
        #expect(fixture.store.token?.accessToken == "new-access")
        #expect(await fixture.server.requests.count == 3)
    }

    @Test func concurrentExpiredRequestsShareOneRefresh() async throws {
        let gate = OAuthTestGate()
        var refresh = OAuthStubResponse.refreshed
        refresh.gate = gate
        let fixture = makeFixture(token: token(), responses: [.accounts, refresh])
        await fixture.manager.restore()
        fixture.clock.now = Self.instant.addingTimeInterval(4_000)

        let first = Task { try await fixture.manager.validAccessToken() }
        await gate.waitUntilEntered()
        // Start the second caller in a main-actor task. It runs through the
        // manager's first suspension before this continuation can resume.
        var second: Task<String, Error>?
        await withCheckedContinuation { started in
            second = Task { @MainActor in
                started.resume()
                return try await fixture.manager.validAccessToken()
            }
        }
        await gate.open()

        #expect(try await first.value == "new-access")
        let secondTask = try #require(second)
        #expect(try await secondTask.value == "new-access")
        let requests = await fixture.server.requests
        #expect(requests.filter { $0.url?.path == "/token" }.count == 1)
        #expect(fixture.store.saveCount == 1)
    }

    @Test func unauthorizedAccountsRefreshOnceAndRetryWithNewBearer() async {
        let fixture = makeFixture(token: token(), responses: [.unauthorized, .refreshed, .accounts])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.count == 2)
        let requests = await fixture.server.requests
        #expect(requests.count == 3)
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test func cloudflareInvalidToken403RefreshesOnceAndRetries() async {
        let fixture = makeFixture(token: token(), responses: [.invalidBearer, .refreshed, .accounts])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.count == 2)
        let requests = await fixture.server.requests
        #expect(requests.count == 3)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test func repeatedCloudflareInvalidToken403ExpiresSession() async {
        let fixture = makeFixture(token: token(), responses: [.invalidBearer, .refreshed, .invalidBearer])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .expired(OAuthError.sessionExpired.localizedDescription))
        #expect(fixture.store.token == nil)
        #expect(await fixture.server.requests.count == 3)
    }

    @Test func secondUnauthorizedResponseExpiresSessionWithoutRefreshLoop() async {
        let fixture = makeFixture(token: token(), responses: [.unauthorized, .refreshed, .unauthorized])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .expired(OAuthError.sessionExpired.localizedDescription))
        #expect(fixture.manager.accounts.isEmpty)
        #expect(fixture.store.token == nil)
        #expect(await fixture.server.requests.count == 3)
    }

    @Test func forbiddenAccountsPreservesSessionAndDoesNotRefresh() async {
        let forbidden = OAuthStubResponse(status: 403, body: #"{"success":false,"errors":[{"code":1001,"message":"Missing account permission"}]}"#)
        let original = token()
        let fixture = makeFixture(token: original, responses: [forbidden])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accountError != nil)
        #expect(fixture.store.token == original)
        #expect(fixture.store.deleteCount == 0)
        #expect(fixture.store.saveCount == 0)
        #expect(await fixture.server.requests.count == 1)
    }

    @Test func cloudflare9109ResourcePermissionErrorPreservesSession() async {
        let forbidden = OAuthStubResponse(status: 403, body: #"{"success":false,"errors":[{"code":9109,"message":"Unauthorized to access requested resource"}]}"#)
        let original = token()
        let fixture = makeFixture(token: original, responses: [forbidden])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accountError != nil)
        #expect(fixture.store.token == original)
        #expect(fixture.store.saveCount == 0)
        #expect(fixture.store.deleteCount == 0)
        #expect(await fixture.server.requests.count == 1)
    }

    @Test func cancelledInitialRestoreLeavesRetryableState() async {
        let cancelled = OAuthStubResponse(status: 0, body: "", error: URLError(.cancelled))
        let original = token()
        let fixture = makeFixture(token: original, responses: [cancelled, .accounts])
        await fixture.manager.restore()
        #expect(!fixture.manager.state.isAuthenticating)
        #expect(fixture.manager.canRetrySession)
        #expect(fixture.store.token == original)
        await fixture.manager.retry()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.count == 2)
    }

    @Test func failedAccountEnvelopeCannotAppearAsLoadedAccounts() async {
        let failed = OAuthStubResponse(status: 200, body: #"{"success":false,"result":[],"errors":[{"code":10000,"message":"Account lookup failed"}]}"#)
        let fixture = makeFixture(token: token(), responses: [failed])
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accountError != nil)
        #expect(fixture.manager.accounts.isEmpty)
    }

    @Test func accountLoadingIncludesEveryPage() async {
        let first = OAuthStubResponse(status: 200, body: #"{"success":true,"result":[{"id":"first","name":"First"}],"result_info":{"total_pages":2}}"#)
        let second = OAuthStubResponse(status: 200, body: #"{"success":true,"result":[{"id":"second","name":"Second"}],"result_info":{"total_pages":2}}"#)
        let fixture = makeFixture(token: token(), responses: [first, second])
        await fixture.manager.restore()
        #expect(fixture.manager.accounts.map(\.id) == ["first", "second"])
        let requests = await fixture.server.requests
        let pages = requests.map {
            URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "page" }?.value
        }
        #expect(pages == ["1", "2"])
    }

    @Test func signOutClearsAccountsAndRevokesRefreshToken() async throws {
        let fixture = makeFixture(token: token(), responses: [.accounts, .init(status: 200, body: "")])
        await fixture.manager.restore()
        await fixture.manager.signOut()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(fixture.store.token == nil)
        let requests = await fixture.server.requests
        let revocation = try #require(requests.last)
        #expect(revocation.httpMethod == "POST")
        #expect(revocation.url?.path == "/revoke")
        let form = try decodeForm(revocation)
        #expect(form["token"] == "old-refresh")
        #expect(form["token_type_hint"] == "refresh_token")
        #expect(form["client_id"] == "test-client")
        await #expect(throws: (any Error).self) { try await fixture.manager.validAccessToken() }
    }

    @Test func revocationFailureLeavesSessionSignedOutWithNotice() async {
        let fixture = makeFixture(token: token(), responses: [.accounts, .init(status: 503, body: "")])
        await fixture.manager.restore()
        await fixture.manager.signOut()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(fixture.store.token == nil)
        #expect(fixture.manager.sessionNotice != nil)
    }

    @Test func signOutWhileBrowserIsOpenCannotResurrectSession() async {
        let gate = OAuthTestGate()
        let authorizer = OAuthTestAuthorizer()
        authorizer.gate = gate
        let fixture = makeFixture(authorizer: authorizer)
        let signIn = Task { await fixture.manager.signIn() }
        await gate.waitUntilEntered()
        #expect(fixture.manager.state.isAuthenticating)
        await fixture.manager.signOut()
        await gate.open()
        await signIn.value
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.store.token == nil)
        #expect(fixture.store.saveCount == 0)
        #expect(await fixture.server.requests.isEmpty)
    }

    @Test func signOutWhileAccountsLoadCannotRestoreOldAccounts() async {
        let gate = OAuthTestGate()
        var response = OAuthStubResponse.accounts
        response.gate = gate
        let fixture = makeFixture(token: token(refresh: nil), responses: [response])
        let restore = Task { await fixture.manager.restore() }
        await gate.waitUntilEntered()
        await fixture.manager.signOut()
        await gate.open()
        await restore.value
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(!fixture.manager.isLoadingAccounts)
        #expect(fixture.store.token == nil)
    }

    @Test func storageReadFailureIsVisibleAndRetryable() async {
        let fixture = makeFixture(token: token(), responses: [.accounts])
        fixture.store.loadError = OAuthTestError.storageUnavailable
        await fixture.manager.restore()
        #expect(!fixture.manager.state.isSignedIn)
        #expect(fixture.manager.state.failureMessage != nil)
        #expect(fixture.manager.canRetrySession)
        #expect(await fixture.server.requests.isEmpty)

        fixture.store.loadError = nil
        await fixture.manager.retry()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.accounts.count == 2)
    }

    @Test func storageWriteFailureDoesNotPublishSignedInSession() async {
        let fixture = makeFixture(responses: [.refreshed])
        fixture.store.saveError = OAuthTestError.storageUnavailable
        await fixture.manager.signIn()
        #expect(!fixture.manager.state.isSignedIn)
        #expect(fixture.manager.state.failureMessage != nil)
        #expect(fixture.store.token == nil)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(await fixture.server.requests.count == 1)
    }

    @Test func refreshedCredentialsSurviveWriteFailureAndPersistOnRetry() async {
        let original = token(expired: true)
        let fixture = makeFixture(token: original, responses: [.refreshed, .accounts, .accounts])
        fixture.store.saveError = OAuthTestError.storageUnavailable
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedIn)
        #expect(fixture.manager.sessionNotice != nil)
        #expect(fixture.store.token == original)

        fixture.store.saveError = nil
        await fixture.manager.retry()
        #expect(fixture.store.token?.accessToken == "new-access")
        #expect(fixture.store.token?.refreshToken == "new-refresh")
        #expect(fixture.manager.sessionNotice == nil)
        let requests = await fixture.server.requests
        #expect(requests.filter { $0.url?.path == "/token" }.count == 1)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
    }

    @Test func storageDeleteFailureStillSignsOutAndReportsPersistenceProblem() async {
        let fixture = makeFixture(token: token(refresh: nil), responses: [.accounts])
        await fixture.manager.restore()
        fixture.store.deleteError = OAuthTestError.storageUnavailable
        await fixture.manager.signOut()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.manager.accounts.isEmpty)
        #expect(fixture.manager.sessionNotice != nil)
        #expect(fixture.manager.canRetrySignOut)
        await #expect(throws: (any Error).self) { try await fixture.manager.validAccessToken() }

        // A view's .task may run again after navigation. It must not undo the
        // user's explicit sign-out by restoring a token that failed deletion.
        await fixture.manager.restore()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.store.loadCount == 1)

        fixture.store.deleteError = nil
        await fixture.manager.signOut()
        #expect(fixture.manager.state == .signedOut)
        #expect(fixture.store.token == nil)
        #expect(!fixture.manager.canRetrySignOut)
        #expect(fixture.manager.sessionNotice == nil)
        #expect(fixture.store.deleteCount == 2)
    }

    private func decodeForm(_ request: URLRequest) throws -> [String: String] {
        let body = try #require(request.httpBody)
        let text = try #require(String(data: body, encoding: .utf8))
        let components = try #require(URLComponents(string: "https://form.example.test/?\(text)"))
        let items = try #require(components.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }
}

@MainActor
private struct OAuthFixture {
    let manager: CloudflareAuthManager
    let store: OAuthMemoryStore
    let server: OAuthTestServer
    let authorizer: OAuthTestAuthorizer
    let clock: OAuthTestClock
    let session: URLSession
}

@MainActor
private final class OAuthTestClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
private final class OAuthMemoryStore: AuthTokenStoring {
    var token: AuthToken?
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?
    private(set) var loadCount = 0
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    init(token: AuthToken?) { self.token = token }

    func load() throws -> AuthToken? {
        loadCount += 1
        if let loadError { throw loadError }
        return token
    }

    func save(_ token: AuthToken) throws {
        saveCount += 1
        if let saveError { throw saveError }
        self.token = token
    }

    func delete() throws {
        deleteCount += 1
        if let deleteError { throw deleteError }
        token = nil
    }
}

@MainActor
private final class OAuthTestAuthorizer: OAuthRedirectAuthorizing {
    enum Callback {
        case valid
        case wrongState
        case wrongRedirect
        case missingCode
        case duplicateState
        case cancelled
    }

    var callback: Callback = .valid
    var gate: OAuthTestGate?
    private(set) var authorizationURL: URL?
    private(set) var callbackScheme: String?

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        authorizationURL = url
        self.callbackScheme = callbackScheme
        if let gate { await gate.wait() }
        if case .cancelled = callback { throw OAuthError.userCancelled }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let state = query.first { $0.name == "state" }!.value!
        let redirect = query.first { $0.name == "redirect_uri" }!.value!
        var result = URLComponents(string: callback == .wrongRedirect
                                   ? "macflare://unexpected-host" : redirect)!
        result.queryItems = [
            URLQueryItem(name: "state", value: callback == .wrongState ? "attacker-state" : state),
        ]
        if callback != .missingCode {
            result.queryItems!.append(URLQueryItem(name: "code", value: "code+with&reserved=characters"))
        }
        if callback == .duplicateState {
            result.queryItems!.append(URLQueryItem(name: "state", value: state))
        }
        return result.url!
    }
}

private enum OAuthTestError: Error {
    case storageUnavailable
    case unexpectedRequest
}

private struct OAuthStubResponse: Sendable {
    let status: Int
    let body: String
    var gate: OAuthTestGate?
    var error: URLError?

    static let accounts = OAuthStubResponse(
        status: 200,
        body: #"{"success":true,"result":[{"id":"account-one","name":"Personal"},{"id":"account-two","name":"Work"}],"errors":[],"messages":[]}"#
    )
    static let refreshed = OAuthStubResponse(
        status: 200,
        body: #"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","scope":"account.read offline_access","expires_in":3600}"#
    )
    static let invalidGrant = OAuthStubResponse(
        status: 400,
        body: #"{"error":"invalid_grant","error_description":"The refresh token has expired."}"#
    )
    static let unauthorized = OAuthStubResponse(status: 401, body: #"{"success":false,"errors":[{"code":10000,"message":"Authentication error"}]}"#)
    static let invalidBearer = OAuthStubResponse(status: 403, body: #"{"success":false,"errors":[{"code":9109,"message":"Invalid access token"}]}"#)
}

/// The gate deliberately ignores cancellation, so tests can deliver a stale
/// browser callback after sign-out and prove it cannot restore the session.
private actor OAuthTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasEntered = false

    func wait() async {
        hasEntered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilEntered() async {
        if hasEntered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor OAuthTestServer {
    private var responses: [OAuthStubResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [OAuthStubResponse]) { self.responses = responses }

    func respond(to request: URLRequest) async throws -> OAuthStubResponse {
        var captured = request
        // URLSession may move a form body to a stream before URLProtocol sees it.
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = body
        }
        requests.append(captured)
        guard !responses.isEmpty else { throw OAuthTestError.unexpectedRequest }
        let response = responses.removeFirst()
        if let gate = response.gate { await gate.wait() }
        if let error = response.error { throw error }
        return response
    }
}

private final class OAuthStubProtocol: URLProtocol {
    nonisolated(unsafe) static var server: OAuthTestServer?
    private var responseTask: Task<Void, Never>?

    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let server = Self.server
        responseTask = Task {
            do {
                guard let server else { throw OAuthTestError.unexpectedRequest }
                let stub = try await server.respond(to: request)
                guard !Task.isCancelled else { return }
                let response = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                                               httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() { responseTask?.cancel() }
}

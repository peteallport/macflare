//
//  OAuthWebSession.swift
//  macflare
//
//  Browser round-trip that returns the OAuth redirect URL.
//

import AuthenticationServices
import Foundation
import Network

#if os(macOS)
import AppKit
#endif

/// Errors surfaced by the OAuth flow. Messages never include token responses.
enum OAuthError: Error, LocalizedError, Equatable {
    case notConfigured
    case userCancelled
    case signInInProgress
    case missingCallbackURL
    case invalidCallbackURL
    case stateMismatch
    case missingAuthorizationCode
    case sessionExpired
    case invalidGrant
    case invalidTokenResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloudflare OAuth client is not configured."
        case .userCancelled:
            return "Sign in was cancelled."
        case .signInInProgress:
            return "A Cloudflare sign-in is already in progress."
        case .missingCallbackURL:
            return "No callback was received from Cloudflare."
        case .invalidCallbackURL:
            return "The sign-in response did not match MacFlare's registered callback. Please try again."
        case .stateMismatch:
            return "The sign-in response failed a security check. Please try again."
        case .missingAuthorizationCode:
            return "Cloudflare did not return an authorization code."
        case .sessionExpired, .invalidGrant:
            return "Your Cloudflare session has expired. Please sign in again."
        case .invalidTokenResponse:
            return "Cloudflare returned an incomplete or invalid session. Please try signing in again."
        case .server(let message):
            return message
        }
    }
}

/// Injectable browser round-trip for the configured public OAuth client.
@MainActor
protocol OAuthRedirectAuthorizing {
    func authorize(url: URL, callbackScheme: String) async throws -> URL
    func authorize(url: URL, redirectURI: String) async throws -> URL
    func cancel()
}

extension OAuthRedirectAuthorizing {
    func authorize(url: URL, redirectURI: String) async throws -> URL {
        try await authorize(url: url, callbackScheme: URL(string: redirectURI)?.scheme ?? "")
    }

    func cancel() {}
}

/// Keeps one browser session alive and resumes its continuation exactly once.
@MainActor
final class WebAuthenticationSessionAuthorizer: NSObject, OAuthRedirectAuthorizing {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var activeID: UUID?
    private let loopback = LoopbackOAuthAuthorizer()

    func authorize(url: URL, redirectURI: String) async throws -> URL {
        if URL(string: redirectURI)?.scheme == "http" {
            guard activeID == nil else { throw OAuthError.signInInProgress }
            let id = UUID()
            activeID = id
            defer { if activeID == id { activeID = nil } }
            return try await loopback.authorize(url: url, redirectURI: redirectURI)
        }
        return try await authorize(url: url, callbackScheme: URL(string: redirectURI)?.scheme ?? "")
    }

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        guard activeID == nil else { throw OAuthError.signInInProgress }
        let id = UUID()
        activeID = id
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { [weak self] callbackURL, error in
                    Task { @MainActor in
                        guard let self else { return }
                        let result: Result<URL, Error>
                        if let error {
                            let nsError = error as NSError
                            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                                result = .failure(OAuthError.userCancelled)
                            } else {
                                result = .failure(error)
                            }
                        } else if let callbackURL {
                            result = .success(callbackURL)
                        } else {
                            result = .failure(OAuthError.missingCallbackURL)
                        }
                        self.finish(id: id, result: result)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                if !session.start() {
                    self.finish(id: id, result: .failure(OAuthError.missingCallbackURL))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.activeID == id else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        loopback.cancel()
        guard let id = activeID else { return }
        let session = session
        finish(id: id, result: .failure(OAuthError.userCancelled))
        session?.cancel()
    }

    private func finish(id: UUID, result: Result<URL, Error>) {
        guard activeID == id else { return }
        let continuation = continuation
        self.continuation = nil
        activeID = nil
        session = nil
        continuation?.resume(with: result)
    }
}

extension WebAuthenticationSessionAuthorizer: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

/// Cloudflare self-managed clients require an HTTP(S) redirect. A native public
/// client receives that redirect on the loopback interface without a web server
/// or client secret. The listener exists only while sign-in is pending.
@MainActor
final class LoopbackOAuthAuthorizer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var activeID: UUID?
    private var connections: [UUID: NWConnection] = [:]
    private let openBrowser: @MainActor (URL) -> Bool

    init(openBrowser: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.openBrowser = openBrowser
    }

    func authorize(url: URL, redirectURI: String) async throws -> URL {
        guard activeID == nil else { throw OAuthError.signInInProgress }
        guard let redirect = URLComponents(string: redirectURI),
              redirect.scheme == "http", redirect.host == "127.0.0.1",
              let portNumber = redirect.port, let rawPort = UInt16(exactly: portNumber), rawPort > 0,
              let port = NWEndpoint.Port(rawValue: rawPort), redirect.user == nil, redirect.password == nil,
              redirect.query == nil, redirect.fragment == nil,
              let expectedState = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "state" })?.value else {
            throw OAuthError.notConfigured
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw OAuthError.server("MacFlare could not open its sign-in callback. Close other MacFlare sign-in windows and try again.")
        }
        let id = UUID()
        activeID = id
        self.listener = listener
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, self.activeID == id else { return }
                        switch state {
                        case .ready:
                            if !self.openBrowser(url) {
                                self.finish(id: id, result: .failure(OAuthError.server("MacFlare could not open your browser for sign-in.")))
                            }
                        case .failed:
                            self.finish(id: id, result: .failure(OAuthError.server("MacFlare could not listen for sign-in on 127.0.0.1:\(portNumber). Close other MacFlare sign-in windows and retry.")))
                        default:
                            break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        guard let self, self.activeID == id else { connection.cancel(); return }
                        let connectionID = UUID()
                        self.connections[connectionID] = connection
                        connection.start(queue: .main)
                        self.receive(connection, connectionID: connectionID, flowID: id, data: Data(), redirect: redirect, expectedState: expectedState)
                    }
                }
                listener.start(queue: .main)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.activeID == id else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        guard let id = activeID else { return }
        finish(id: id, result: .failure(OAuthError.userCancelled))
    }

    private func receive(_ connection: NWConnection, connectionID: UUID, flowID: UUID, data: Data, redirect: URLComponents, expectedState: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] chunk, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.activeID == flowID else { connection.cancel(); return }
                var received = data
                if let chunk { received.append(chunk) }
                guard error == nil, received.count <= 8_192 else {
                    self.respond(connection, connectionID: connectionID, status: "400 Bad Request", body: "Invalid callback.")
                    return
                }
                guard let request = String(data: received, encoding: .utf8), request.contains("\r\n\r\n") else {
                    if isComplete {
                        self.respond(connection, connectionID: connectionID, status: "400 Bad Request", body: "Incomplete callback.")
                    } else {
                        self.receive(connection, connectionID: connectionID, flowID: flowID, data: received, redirect: redirect, expectedState: expectedState)
                    }
                    return
                }
                let callbackURL: URL
                do {
                    callbackURL = try LoopbackOAuthCallback.parse(
                        request: request,
                        redirectURI: redirect.string ?? "",
                        expectedState: expectedState
                    )
                } catch {
                    self.respond(connection, connectionID: connectionID, status: "400 Bad Request", body: "The callback did not match this sign-in. Return to MacFlare and try again.")
                    return
                }
                // Finish only after the small response is handed to the socket.
                self.respond(connection, connectionID: connectionID, status: "200 OK", body: "You can close this tab and return to MacFlare.") {
                    self.finish(id: flowID, result: .success(callbackURL))
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, connectionID: UUID, status: String, body: String, completion: (@MainActor () -> Void)? = nil) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                connection.cancel()
                self?.connections.removeValue(forKey: connectionID)
                completion?()
            }
        })
    }

    private func finish(id: UUID, result: Result<URL, Error>) {
        guard activeID == id else { return }
        let continuation = continuation
        self.continuation = nil
        activeID = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        continuation?.resume(with: result)
    }
}

/// Pure parser shared by the loopback transport and deterministic callback tests.
enum LoopbackOAuthCallback {
    static func parse(request: String, redirectURI: String, expectedState: String) throws -> URL {
        guard request.utf8.count <= 8_192, request.contains("\r\n\r\n"),
              let redirect = URLComponents(string: redirectURI),
              redirect.scheme == "http", redirect.host == "127.0.0.1", let port = redirect.port,
              (1 ... 65_535).contains(port), redirect.user == nil, redirect.password == nil,
              redirect.query == nil, redirect.fragment == nil, !expectedState.isEmpty else {
            throw OAuthError.invalidCallbackURL
        }
        let headers = request.components(separatedBy: "\r\n\r\n")[0].components(separatedBy: "\r\n")
        let first = (headers.first ?? "").split(separator: " ")
        let hosts = headers.dropFirst().filter { $0.lowercased().hasPrefix("host:") }
        guard first.count == 3, first[0] == "GET", ["HTTP/1.0", "HTTP/1.1"].contains(String(first[2])),
              hosts.count == 1, hosts[0].dropFirst(5).trimmingCharacters(in: .whitespaces) == "127.0.0.1:\(port)",
              let target = URLComponents(string: String(first[1])), target.scheme == nil, target.host == nil,
              target.percentEncodedPath == redirect.percentEncodedPath, target.fragment == nil else {
            throw OAuthError.invalidCallbackURL
        }
        let states = (target.queryItems ?? []).filter { $0.name == "state" }
        guard states.count == 1, states[0].value == expectedState else { throw OAuthError.stateMismatch }
        var callback = redirect
        callback.percentEncodedQuery = target.percentEncodedQuery
        guard let callbackURL = callback.url else { throw OAuthError.invalidCallbackURL }
        return callbackURL
    }
}

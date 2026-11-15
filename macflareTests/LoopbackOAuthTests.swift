//
//  LoopbackOAuthTests.swift
//  macflareTests
//
//  Created by Peter C. Allport on 10/16/26.
//

import Foundation
import Testing
@testable import macflare

/// Exercises the real loopback listener with an injected browser opener. These
/// tests exchange only synthetic callbacks on 127.0.0.1, without opening a browser.
@Suite(.serialized)
@MainActor
struct LoopbackOAuthTests {
    @Test(.timeLimit(.minutes(1)))
    func listenerAcceptsMatchingCallbackAfterRejectingUnrelatedRequest() async throws {
        let redirect = "http://127.0.0.1:18976/oauth/callback"
        let expected = URL(string: "\(redirect)?code=test-code&state=expected")!
        let authorizationURL = URL(string: "https://oauth.example.test/auth?state=expected")!
        var browserRequest: Task<(Data, URLResponse), Error>?
        var openedURL: URL?
        let authorizer = LoopbackOAuthAuthorizer { url in
            openedURL = url
            browserRequest = Task {
                let unrelated = URL(string: "\(redirect)?code=wrong-code&state=wrong-state")!
                let (_, rejection) = try await URLSession.shared.data(from: unrelated)
                #expect((rejection as? HTTPURLResponse)?.statusCode == 400)
                return try await URLSession.shared.data(from: expected)
            }
            return true
        }
        defer { authorizer.cancel() }

        let callback = try await authorizer.authorize(url: authorizationURL, redirectURI: redirect)
        #expect(openedURL == authorizationURL)
        #expect(callback == expected)
        let request = try #require(browserRequest)
        let (body, response) = try await request.value
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(!body.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingReadyListenerCompletesAuthorization() async {
        let redirect = "http://127.0.0.1:18977/oauth/callback"
        let authorizationURL = URL(string: "https://oauth.example.test/auth?state=expected")!
        var authorizer: LoopbackOAuthAuthorizer?
        authorizer = LoopbackOAuthAuthorizer { _ in
            authorizer?.cancel()
            return true
        }
        defer { authorizer?.cancel() }

        await #expect(throws: OAuthError.userCancelled) {
            try await authorizer!.authorize(url: authorizationURL, redirectURI: redirect)
        }
    }
}

//
//  AuthState.swift
//  macflare
//
//  High-level authentication state that drives root navigation.
//

import Foundation

/// High-level authentication state used to switch the app's root view.
enum AuthState: Equatable {
    case signedOut
    case authenticating
    case signedIn
    /// Sign-in failed; the associated value is a user-presentable message.
    case failed(String)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var isAuthenticating: Bool {
        if case .authenticating = self { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

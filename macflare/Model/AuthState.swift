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
    case restoring
    /// The saved session was rejected or cannot be refreshed.
    case expired(String)
    case signedIn
    /// Sign-in failed; the associated value is a user-presentable message.
    case failed(String)

    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }

    var isAuthenticating: Bool {
        switch self {
        case .authenticating, .restoring: return true
        default: return false
        }
    }

    var failureMessage: String? {
        switch self {
        case .failed(let message), .expired(let message): return message
        default: return nil
        }
    }
}

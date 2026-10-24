//
//  WelcomeView.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import AppKit
import SwiftUI
#if DEBUG
import Inject
#endif

@MainActor
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.state = .active
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    }
}

@MainActor
struct WelcomeView: View {
#if DEBUG
    @Inject.ObserveInjection var inject
#endif
    @Environment(CloudflareAuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App Icon/Logo
            Image(systemName: "cloud.fill")
                .font(.system(size: 80, weight: .ultraLight))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            // Welcome Text
            VStack(spacing: 16) {
                Text("Macflare")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("welcomeTitle")

                Text("Cloudflare for power users on macOS.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("welcomeSubtitle")
            }

            Spacer()

            // Action Buttons
            VStack(spacing: 16) {
                Button {
                    Task { await authManager.signIn() }
                } label: {
                    if authManager.state.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign in with Cloudflare")
                    }
                }
                .disabled(authManager.state.isAuthenticating)
                .accessibilityIdentifier("cloudflareSignInButton")

                if authManager.state.isAuthenticating {
                    Button("Cancel") { Task { await authManager.signOut() } }
                        .accessibilityIdentifier("cancelSignInButton")
                }
                if authManager.canRetrySession {
                    Button("Retry Session") { Task { await authManager.retry() } }
                        .accessibilityIdentifier("retrySessionButton")
                    Button("Sign Out") { Task { await authManager.signOut() } }
                }

                if authManager.canRetrySignOut {
                    Button("Remove Saved Session") { Task { await authManager.signOut() } }
                        .accessibilityIdentifier("removeSavedSessionButton")
                }
                if let notice = authManager.sessionNotice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let message = authManager.state.failureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity,
               maxHeight: .infinity)
        .background(VisualEffectView().ignoresSafeArea())

#if DEBUG
        .enableInjection()
#endif

    }
}

#Preview {
    WelcomeView()
        .environment(CloudflareAuthManager())
}

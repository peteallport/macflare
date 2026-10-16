//
//  WelcomeView.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import SwiftUI
import AppKit
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
                Button("Login with Cloudflare") {
                    // Authentication is not implemented in this prototype yet.
                }
                .accessibilityIdentifier("cloudflareLoginButton")
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
}

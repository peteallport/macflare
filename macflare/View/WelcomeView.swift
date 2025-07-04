//
//  WelcomeView.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.state = .active
        return effectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    }
}

struct WelcomeView: View {
    @ObservedObject var authManager: CloudflareAuthManager
    
    var body: some View {
        Group {
            switch authManager.authState {
            case .unauthenticated:
                WelcomeContentView(authManager: authManager)
            case .authenticating:
                AuthenticatingView()
            case .authenticated:
                DashboardView(authManager: authManager)
            case .failed(let error):
                ErrorView(error: error, authManager: authManager)
            }
        }
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
            // Automatically try to refresh token if needed
            Task {
                await authManager.refreshTokenIfNeeded()
            }
        }
    }
}

// MARK: - Welcome Content

struct WelcomeContentView: View {
    @ObservedObject var authManager: CloudflareAuthManager
    
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
                
                Text("Cloudflare for power users on macOS.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                if authManager.networkState == .disconnected {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.red)
                        Text("No internet connection")
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 16) {
                Button(action: {
                    Task {
                        await authManager.authenticate()
                    }
                }) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        Text(authManager.isLoading ? "Authenticating..." : "Login with Cloudflare")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(authManager.isLoading || authManager.networkState == .disconnected)
                
                if let errorMessage = authManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                
                // OAuth Setup Instructions
                if authManager.networkState == .connected {
                    VStack(spacing: 8) {
                        Text("First time setup:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            InstructionRow(step: "1", text: "Create an OAuth app at dash.cloudflare.com")
                            InstructionRow(step: "2", text: "Set redirect URI: macflare://oauth/callback")
                            InstructionRow(step: "3", text: "Update client credentials in the app")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Authenticating View

struct AuthenticatingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Animated Cloud Icon
            Image(systemName: "cloud.fill")
                .font(.system(size: 60, weight: .ultraLight))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            
            VStack(spacing: 12) {
                Text("Authenticating...")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Please complete the authentication in your browser")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 200)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView().ignoresSafeArea())
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    @ObservedObject var authManager: CloudflareAuthManager
    
    var body: some View {
        VStack(spacing: 30) {
            // Error Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)
            
            VStack(spacing: 16) {
                Text("Authentication Failed")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                Button("Try Again") {
                    Task {
                        await authManager.authenticate()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Cancel") {
                    authManager.authState = .unauthenticated
                    authManager.errorMessage = nil
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView().ignoresSafeArea())
    }
}

// MARK: - Helper Components

struct InstructionRow: View {
    let step: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(step)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
                .frame(width: 16, alignment: .leading)
            Text(text)
                .multilineTextAlignment(.leading)
        }
    }
}

#Preview {
    WelcomeView(authManager: CloudflareAuthManager(modelContext: ModelContext(try! ModelContainer(for: CloudflareAccount.self))))
}

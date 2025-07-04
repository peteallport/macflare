//
//  macflareApp.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import SwiftData
import SwiftUI
import AppKit

@main
struct macflareApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            CloudflareAccount.self,
            CloudflareZone.self,
            DNSRecord.self,
            OfflineAction.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    @StateObject private var authManager: CloudflareAuthManager = {
        // Create a temporary model context for initialization
        let tempContainer = try! ModelContainer(for: Schema([
            CloudflareAccount.self,
            CloudflareZone.self,
            DNSRecord.self,
            OfflineAction.self
        ]))
        return CloudflareAuthManager(modelContext: tempContainer.mainContext)
    }()

    var body: some Scene {
        WindowGroup {
            WelcomeView(authManager: authManager)
                .background(.clear)
                .onAppear {
                    configureWindow()
                    setupAuthManager()
                }
                .onOpenURL { url in
                    handleOAuthCallback(url: url)
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .newItem) {
                Button("Sign Out") {
                    Task {
                        await authManager.logout()
                    }
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])
                .disabled(authManager.authState == .unauthenticated)
            }
        }
    }
    
    private func configureWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
    }
    
    private func setupAuthManager() {
        // Update the auth manager to use the shared model container
        authManager.updateModelContext(sharedModelContainer.mainContext)
    }
    
    private func handleOAuthCallback(url: URL) {
        // The OAuth callback will be handled by ASWebAuthenticationSession
        // but we can add additional processing here if needed
        print("Received OAuth callback: \(url)")
    }
}


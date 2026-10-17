//
//  macflareApp.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import SwiftUI
import AppKit
@_exported import Inject

@main
struct MacflareApp: App {
    @State private var authManager = CloudflareAuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .background(Color.clear)
                .task {
                    // Hosted unit tests inject their own session dependencies.
                    // Never restore the user's real credentials in the test host.
                    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
                    await authManager.restore()
                }
                .onAppear { configureWindow() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 500)
        .commands {
            CommandGroup(replacing: .windowSize) {}
            #if DEBUG
            CommandMenu("Development") {
                Button("Refresh Cloudflare Session") {
                    Task { await authManager.loadAccounts(forceRefresh: true) }
                }
                .disabled(!authManager.state.isSignedIn || authManager.isLoadingAccounts)
            }
            #endif
        }
    }

    private func configureWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.standardWindowButton(.closeButton)?.isHidden = false
            }
        }
    }
}

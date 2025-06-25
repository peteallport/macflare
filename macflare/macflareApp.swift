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
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .background(.clear)
                .onAppear {
                    configureWindow()
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 500)
        .commands {
            CommandGroup(replacing: .windowSize) {}
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
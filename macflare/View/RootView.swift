//
//  RootView.swift
//  macflare
//
//  Created by Peter C. Allport on 6/3/26.
//
//  Switches between the welcome/login screen and the main content based on
//  authentication state.
//

import SwiftUI

struct RootView: View {
    @Environment(CloudflareAuthManager.self) private var authManager

    var body: some View {
        if authManager.state.isSignedIn {
            AccountsView()
        } else {
            WelcomeView()
        }
    }
}

#Preview {
    RootView()
        .environment(CloudflareAuthManager())
}

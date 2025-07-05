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
    @Inject.ObserveInjection var inject
    
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
            }
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 16) {
                Button("Login with Cloudflare") {
                    
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity,
               maxHeight: .infinity)
        .background(VisualEffectView().ignoresSafeArea())

#if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
#endif
        .enableInjection()

    }
}

#Preview {
    WelcomeView()
}

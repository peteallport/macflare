//
//  AccountsView.swift
//  macflare
//
//  Created by Peter C. Allport on 10/16/26.
//

import SwiftUI

/// The accounts granted to this MacFlare session.
struct AccountsView: View {
    @Environment(CloudflareAuthManager.self) private var authManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Cloudflare accounts", systemImage: "cloud.fill")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await authManager.loadAccounts() }
                }
                .disabled(authManager.isLoadingAccounts)
                .accessibilityIdentifier("refreshAccountsButton")
                Button("Sign Out") {
                    Task { await authManager.signOut() }
                }
                .accessibilityIdentifier("signOutButton")
            }

            if let notice = authManager.sessionNotice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            if authManager.isLoadingAccounts {
                ProgressView("Loading accounts…")
                    .accessibilityIdentifier("accountsLoading")
            }
            if let message = authManager.accountError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).foregroundStyle(.red)
                    Button("Retry") { Task { await authManager.loadAccounts() } }
                        .disabled(authManager.isLoadingAccounts)
                }
                .accessibilityIdentifier("accountsError")
            }
            if !authManager.isLoadingAccounts && authManager.accountError == nil && authManager.accounts.isEmpty {
                ContentUnavailableView("No accounts available", systemImage: "cloud", description: Text("No Cloudflare accounts were returned for this session."))
            } else {
                List(authManager.accounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name).font(.headline)
                        Text(account.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("cloudflareAccountsList")
            }
            Text("Account access is read only.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 400)
    }
}

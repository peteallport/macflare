//
//  DashboardView.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @ObservedObject var authManager: CloudflareAuthManager
    @Query private var accounts: [CloudflareAccount]
    @State private var selectedTab: DashboardTab = .overview
    
    enum DashboardTab: String, CaseIterable {
        case overview = "Overview"
        case dns = "DNS"
        case analytics = "Analytics"
        case security = "Security"
        case workers = "Workers"
        case cache = "Cache"
        
        var icon: String {
            switch self {
            case .overview: return "chart.bar.doc.horizontal"
            case .dns: return "globe"
            case .analytics: return "chart.line.uptrend.xyaxis"
            case .security: return "shield"
            case .workers: return "gear"
            case .cache: return "externaldrive"
            }
        }
    }
    
    var currentAccount: CloudflareAccount? {
        if case .authenticated(let account) = authManager.authState {
            return account
        }
        return nil
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // User Header
                if let account = currentAccount {
                    UserHeaderView(account: account, authManager: authManager)
                        .padding()
                }
                
                Divider()
                
                // Navigation Tabs
                List(DashboardTab.allCases, id: \.self, selection: $selectedTab) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
                .listStyle(.sidebar)
                
                Spacer()
                
                // Network Status
                NetworkStatusView(networkState: authManager.networkState)
                    .padding()
            }
            .frame(minWidth: 200)
        } detail: {
            // Main Content
            Group {
                switch selectedTab {
                case .overview:
                    OverviewView(authManager: authManager)
                case .dns:
                    DNSView(authManager: authManager)
                case .analytics:
                    AnalyticsView(authManager: authManager)
                case .security:
                    SecurityView(authManager: authManager)
                case .workers:
                    WorkersView(authManager: authManager)
                case .cache:
                    CacheView(authManager: authManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Macflare")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    Task {
                        await authManager.refreshTokenIfNeeded()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }
}

// MARK: - User Header

struct UserHeaderView: View {
    let account: CloudflareAccount
    let authManager: CloudflareAuthManager
    @State private var showingLogoutAlert = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Avatar
            AsyncImage(url: URL(string: account.avatarURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(.quaternary)
                    .overlay {
                        Text(account.name.prefix(1))
                            .font(.title2)
                            .fontWeight(.medium)
                    }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            
            // User Info
            VStack(spacing: 4) {
                Text(account.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if let org = account.organizationName {
                    Text(org)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            // Logout Button
            Button("Sign Out") {
                showingLogoutAlert = true
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .alert("Sign Out", isPresented: $showingLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    await authManager.logout()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
}

// MARK: - Network Status

struct NetworkStatusView: View {
    let networkState: NetworkState
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var statusColor: Color {
        switch networkState {
        case .connected: return .green
        case .disconnected: return .red
        case .connecting: return .orange
        }
    }
    
    private var statusText: String {
        switch networkState {
        case .connected: return "Online"
        case .disconnected: return "Offline"
        case .connecting: return "Connecting..."
        }
    }
}

// MARK: - Dashboard Content Views

struct OverviewView: View {
    let authManager: CloudflareAuthManager
    @Query private var zones: [CloudflareZone]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 300), spacing: 20)
            ], spacing: 20) {
                // Account Summary
                DashboardCard(title: "Account Summary", icon: "person.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        StatRow(label: "Active Zones", value: "\(zones.count)")
                        StatRow(label: "Total DNS Records", value: "\(zones.flatMap(\.dnsRecords).count)")
                        StatRow(label: "Last Sync", value: formatLastSync())
                    }
                }
                
                // Quick Actions
                DashboardCard(title: "Quick Actions", icon: "bolt.circle") {
                    VStack(spacing: 12) {
                        ActionButton(title: "Add Zone", icon: "plus.circle", action: {})
                        ActionButton(title: "Purge Cache", icon: "trash.circle", action: {})
                        ActionButton(title: "Security Check", icon: "shield.checkered", action: {})
                    }
                }
                
                // Recent Activity
                DashboardCard(title: "Recent Activity", icon: "clock.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            ActivityRow(
                                title: "DNS Record Updated", 
                                zone: "example.com",
                                time: "2 minutes ago"
                            )
                        }
                    }
                }
                
                // System Status
                DashboardCard(title: "Cloudflare Status", icon: "checkmark.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(service: "API", status: .operational)
                        StatusRow(service: "Dashboard", status: .operational)
                        StatusRow(service: "Workers", status: .operational)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Overview")
    }
    
    private func formatLastSync() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: Date().addingTimeInterval(-120), relativeTo: Date())
    }
}

// MARK: - Other Dashboard Views (Placeholders)

struct DNSView: View {
    let authManager: CloudflareAuthManager
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("DNS Management")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Manage your DNS records")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("DNS")
    }
}

struct AnalyticsView: View {
    let authManager: CloudflareAuthManager
    
    var body: some View {
        VStack {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Analytics")
                .font(.title2)
                .fontWeight(.semibold)
            Text("View your website analytics")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Analytics")
    }
}

struct SecurityView: View {
    let authManager: CloudflareAuthManager
    
    var body: some View {
        VStack {
            Image(systemName: "shield")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Security")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Manage security settings")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Security")
    }
}

struct WorkersView: View {
    let authManager: CloudflareAuthManager
    
    var body: some View {
        VStack {
            Image(systemName: "gear")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Workers")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Manage Cloudflare Workers")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Workers")
    }
}

struct CacheView: View {
    let authManager: CloudflareAuthManager
    
    var body: some View {
        VStack {
            Image(systemName: "externaldrive")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Cache")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Manage cache settings")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Cache")
    }
}

// MARK: - Reusable Components

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            content
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(.borderless)
    }
}

struct ActivityRow: View {
    let title: String
    let zone: String
    let time: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            HStack {
                Text(zone)
                    .font(.caption)
                    .foregroundStyle(.blue)
                Spacer()
                Text(time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusRow: View {
    let service: String
    let status: ServiceStatus
    
    enum ServiceStatus {
        case operational
        case degraded
        case down
        
        var color: Color {
            switch self {
            case .operational: return .green
            case .degraded: return .orange
            case .down: return .red
            }
        }
        
        var text: String {
            switch self {
            case .operational: return "Operational"
            case .degraded: return "Degraded"
            case .down: return "Down"
            }
        }
    }
    
    var body: some View {
        HStack {
            Text(service)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
    }
}

#Preview {
    DashboardView(authManager: CloudflareAuthManager(modelContext: ModelContext(try! ModelContainer(for: CloudflareAccount.self))))
}
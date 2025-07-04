//
//  CloudflareAuthManager.swift
//  macflare
//
//  Created by Peter C. Allport on 6/24/25.
//

import Foundation
import SwiftUI
import SwiftData
import AuthenticationServices
import Network
import Security

@MainActor
final class CloudflareAuthManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var authState: AuthenticationState = .unauthenticated
    @Published var networkState: NetworkState = .connected
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let keychainService = "com.macflare.tokens"
    private let keychainAccount = "cloudflare_oauth"
    private var networkMonitor: NWPathMonitor?
    private var refreshTimer: Timer?
    private var modelContext: ModelContext
    
    // OAuth Configuration
    private let clientId = "YOUR_CLOUDFLARE_CLIENT_ID" // TODO: Replace with actual client ID
    private let clientSecret = "YOUR_CLOUDFLARE_CLIENT_SECRET" // TODO: Replace with actual client secret
    private let redirectURI = "macflare://oauth/callback"
    private let authorizationEndpoint = "https://dash.cloudflare.com/oauth2/auth"
    private let tokenEndpoint = "https://dash.cloudflare.com/oauth2/token"
    private let userInfoEndpoint = "https://api.cloudflare.com/client/v4/user"
    
    // Scopes for all Cloudflare services
    private let scopes = [
        "zone:read",
        "zone:edit", 
        "dns_records:read",
        "dns_records:edit",
        "analytics:read",
        "page_rules:read",
        "page_rules:edit",
        "cache_purge:edit",
        "ssl:read",
        "ssl:edit",
        "workers:read",
        "workers:edit",
        "account:read",
        "user:read"
    ].joined(separator: " ")
    
    // MARK: - Initialization
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupNetworkMonitoring()
        loadStoredToken()
    }
    
    // MARK: - Public Methods
    
    func authenticate() async {
        guard networkState == .connected else {
            errorMessage = "No internet connection available"
            return
        }
        
        authState = .authenticating
        isLoading = true
        errorMessage = nil
        
        do {
            let token = try await performOAuthFlow()
            try saveTokenToKeychain(token)
            let account = try await fetchUserInfo(token: token)
            await saveAccountToStorage(account)
            authState = .authenticated(account)
            setupTokenRefreshTimer(token: token)
        } catch {
            authState = .failed(error)
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func logout() async {
        // Stop timer
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        // Remove token from keychain
        removeTokenFromKeychain()
        
        // Clear stored data
        await clearStoredData()
        
        // Update state
        authState = .unauthenticated
        errorMessage = nil
    }
    
    func refreshTokenIfNeeded() async {
        guard case .authenticated = authState else { return }
        
        if let token = loadTokenFromKeychain(), token.isExpired {
            await refreshToken()
        }
    }
    
    func updateModelContext(_ newContext: ModelContext) {
        modelContext = newContext
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.networkState = path.status == .satisfied ? .connected : .disconnected
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor?.start(queue: queue)
    }
    
    private func loadStoredToken() {
        if let token = loadTokenFromKeychain(), !token.isExpired {
            Task {
                do {
                    let account = try await fetchStoredAccount()
                    authState = .authenticated(account)
                    setupTokenRefreshTimer(token: token)
                } catch {
                    // Token exists but account data is invalid, re-authenticate
                    removeTokenFromKeychain()
                }
            }
        }
    }
    
    private func performOAuthFlow() async throws -> CloudflareOAuthToken {
        return try await withCheckedThrowingContinuation { continuation in
            
            // Construct authorization URL
            var components = URLComponents(string: authorizationEndpoint)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "state", value: UUID().uuidString)
            ]
            
            guard let authURL = components.url else {
                continuation.resume(throwing: AuthError.invalidURL)
                return
            }
            
            // Present authentication session
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "macflare"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                    return
                }
                
                // Exchange code for token
                Task {
                    do {
                        let token = try await self.exchangeCodeForToken(code: code)
                        continuation.resume(returning: token)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    
    private func exchangeCodeForToken(code: String) async throws -> CloudflareOAuthToken {
        guard let url = URL(string: tokenEndpoint) else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURI
        ]
        
        let parameterString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = parameterString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        return CloudflareOAuthToken(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            tokenType: tokenResponse.token_type,
            expiresIn: tokenResponse.expires_in,
            scope: tokenResponse.scope ?? scopes,
            createdAt: Date()
        )
    }
    
    private func fetchUserInfo(token: CloudflareOAuthToken) async throws -> CloudflareAccount {
        guard let url = URL(string: userInfoEndpoint) else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.userInfoFailed
        }
        
        let userResponse = try JSONDecoder().decode(UserResponse.self, from: data)
        
        return CloudflareAccount(
            id: userResponse.result.id,
            email: userResponse.result.email,
            name: userResponse.result.first_name + " " + userResponse.result.last_name,
            organizationName: userResponse.result.organizations?.first?.name,
            avatarURL: nil
        )
    }
    
    private func refreshToken() async {
        guard let currentToken = loadTokenFromKeychain(),
              let refreshToken = currentToken.refreshToken else {
            await logout()
            return
        }
        
        do {
            let newToken = try await performTokenRefresh(refreshToken: refreshToken)
            try saveTokenToKeychain(newToken)
            setupTokenRefreshTimer(token: newToken)
        } catch {
            await logout()
        }
    }
    
    private func performTokenRefresh(refreshToken: String) async throws -> CloudflareOAuthToken {
        guard let url = URL(string: tokenEndpoint) else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "grant_type": "refresh_token",
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken
        ]
        
        let parameterString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = parameterString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        return CloudflareOAuthToken(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token ?? refreshToken,
            tokenType: tokenResponse.token_type,
            expiresIn: tokenResponse.expires_in,
            scope: tokenResponse.scope ?? scopes,
            createdAt: Date()
        )
    }
    
    private func setupTokenRefreshTimer(token: CloudflareOAuthToken) {
        refreshTimer?.invalidate()
        
        // Refresh token 5 minutes before expiration
        let refreshTime = max(TimeInterval(token.expiresIn) - 300, 300)
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshTime, repeats: false) { [weak self] _ in
            Task {
                await self?.refreshToken()
            }
        }
    }
    
    // MARK: - Keychain Methods
    
    private func saveTokenToKeychain(_ token: CloudflareOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError
        }
    }
    
    private func loadTokenFromKeychain() -> CloudflareOAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = try? JSONDecoder().decode(CloudflareOAuthToken.self, from: data) else {
            return nil
        }
        
        return token
    }
    
    private func removeTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: true
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Storage Methods
    
    private func saveAccountToStorage(_ account: CloudflareAccount) async {
        modelContext.insert(account)
        try? modelContext.save()
    }
    
    private func fetchStoredAccount() async throws -> CloudflareAccount {
        let descriptor = FetchDescriptor<CloudflareAccount>(
            predicate: #Predicate<CloudflareAccount> { $0.isActive == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        let accounts = try modelContext.fetch(descriptor)
        guard let account = accounts.first else {
            throw AuthError.noStoredAccount
        }
        
        return account
    }
    
    private func clearStoredData() async {
        let accountDescriptor = FetchDescriptor<CloudflareAccount>()
        let accounts = try? modelContext.fetch(accountDescriptor)
        accounts?.forEach { modelContext.delete($0) }
        
        try? modelContext.save()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension CloudflareAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Response Models

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let token_type: String
    let expires_in: Int
    let scope: String?
}

private struct UserResponse: Codable {
    let result: UserResult
}

private struct UserResult: Codable {
    let id: String
    let email: String
    let first_name: String
    let last_name: String
    let organizations: [Organization]?
}

private struct Organization: Codable {
    let name: String
    let id: String
}

// MARK: - Error Types

enum AuthError: LocalizedError {
    case invalidURL
    case invalidCallback
    case tokenExchangeFailed
    case tokenRefreshFailed
    case userInfoFailed
    case keychainError
    case noStoredAccount
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidCallback:
            return "Invalid OAuth callback"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for token"
        case .tokenRefreshFailed:
            return "Failed to refresh token"
        case .userInfoFailed:
            return "Failed to fetch user information"
        case .keychainError:
            return "Keychain operation failed"
        case .noStoredAccount:
            return "No stored account found"
        }
    }
}
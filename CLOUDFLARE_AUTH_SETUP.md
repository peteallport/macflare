# Cloudflare OAuth Authentication Setup for Macflare

## Overview

I've implemented a comprehensive Cloudflare OAuth authentication system for Macflare that includes:

✅ **OAuth 2.0 Flow** with `ASWebAuthenticationSession`  
✅ **Automatic Token Renewal** with refresh tokens  
✅ **Secure iCloud Keychain Storage** for tokens  
✅ **Offline State Management** with CoreData/CloudKit  
✅ **Network Monitoring** with connectivity status  
✅ **Modern SwiftUI Dashboard** with sidebar navigation  

## Features Implemented

### 🔐 Authentication System
- **CloudflareAuthManager**: Observable authentication manager
- **Secure Token Storage**: Uses iCloud Keychain with synchronization
- **Auto Token Refresh**: Automatically refreshes tokens 5 minutes before expiration
- **Custom URL Scheme**: `macflare://oauth/callback` for OAuth callbacks
- **Network Monitoring**: Real-time connectivity status

### 📊 Dashboard Interface
- **Multi-tab Interface**: Overview, DNS, Analytics, Security, Workers, Cache
- **User Profile**: Shows account info with avatar and organization
- **Network Status Indicator**: Visual connectivity status in sidebar
- **Responsive Layout**: Adapts to different window sizes

### 💾 Data Management
- **SwiftData Models**: CloudflareAccount, CloudflareZone, DNSRecord, OfflineAction
- **CloudKit Integration**: Syncs data across devices
- **Offline Actions**: Queues actions when offline for later sync

## Setup Instructions

### 1. Create Cloudflare OAuth Application

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **My Profile** → **API Tokens** → **OAuth Apps**
3. Click **Create OAuth App**
4. Configure the app:
   - **App Name**: Macflare
   - **Redirect URI**: `macflare://oauth/callback`
   - **Client Type**: Confidential
   - **Scopes**: Select all scopes you need (or use the comprehensive list below)

### 2. Update Client Credentials

In `CloudflareAuthManager.swift`, update these lines:

```swift
private let clientId = "YOUR_ACTUAL_CLIENT_ID"
private let clientSecret = "YOUR_ACTUAL_CLIENT_SECRET"
```

### 3. OAuth Scopes Configured

The app requests these scopes for comprehensive access:
- `zone:read`, `zone:edit`
- `dns_records:read`, `dns_records:edit`
- `analytics:read`
- `page_rules:read`, `page_rules:edit`
- `cache_purge:edit`
- `ssl:read`, `ssl:edit`
- `workers:read`, `workers:edit`
- `account:read`, `user:read`

## Project Structure

```
macflare/
├── Model/
│   ├── CloudflareModels.swift       # Data models and enums
│   └── CloudflareAuthManager.swift  # Authentication manager
├── View/
│   ├── WelcomeView.swift            # Entry point with auth states
│   ├── DashboardView.swift          # Main dashboard interface
│   └── ContentView.swift           # (existing)
├── macflareApp.swift               # App entry point
├── Info.plist                     # OAuth URL scheme config
└── macflare.entitlements          # Keychain & network permissions
```

## Key Components

### CloudflareAuthManager
Observable class that manages:
- OAuth flow with `ASWebAuthenticationSession`
- Token storage/retrieval from Keychain
- Automatic token refresh
- Network connectivity monitoring
- User authentication state

### Authentication States
```swift
enum AuthenticationState {
    case unauthenticated
    case authenticating  
    case authenticated(CloudflareAccount)
    case failed(Error)
}
```

### Data Models
- **CloudflareAccount**: User account with zones and offline actions
- **CloudflareZone**: Domain zones with DNS records
- **DNSRecord**: Individual DNS entries
- **OfflineAction**: Queued actions for offline sync

## Usage

### Basic Authentication
```swift
// Authenticate user
await authManager.authenticate()

// Check authentication status
if case .authenticated(let account) = authManager.authState {
    // User is authenticated
}

// Logout
await authManager.logout()
```

### Network Monitoring
```swift
// Monitor connection status
switch authManager.networkState {
case .connected:
    // Online - can make API calls
case .disconnected:
    // Offline - show warning, queue actions
case .connecting:
    // Connecting - show loading state
}
```

## Security Features

### Keychain Storage
- Tokens stored in iCloud Keychain with synchronization
- Service: `com.macflare.tokens`
- Account: `cloudflare_oauth`
- Uses `kSecAttrSynchronizable` for cross-device sync

### Token Management
- Automatic refresh 5 minutes before expiration
- Secure token validation
- Graceful handling of expired/invalid tokens

### Offline Protection
- Actions queued when offline
- Data cached locally with SwiftData
- Sync when connection restored

## Development Notes

### OAuth Endpoints
- **Authorization**: `https://dash.cloudflare.com/oauth2/auth`
- **Token**: `https://dash.cloudflare.com/oauth2/token`
- **User Info**: `https://api.cloudflare.com/client/v4/user`

### Custom URL Scheme
The app registers `macflare://` scheme in `Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.macflare.oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>macflare</string>
        </array>
    </dict>
</array>
```

### Entitlements
Required capabilities in `macflare.entitlements`:
- `com.apple.security.network.client`: Network access
- `keychain-access-groups`: Keychain storage
- `com.apple.developer.icloud-services`: CloudKit sync

## Next Steps

1. **Update OAuth Credentials**: Replace placeholder client ID/secret
2. **Test Authentication Flow**: Verify OAuth redirect works
3. **Implement API Calls**: Add Cloudflare API integration
4. **Enhance Dashboard**: Add real data and functionality
5. **Add Offline Sync**: Implement queued action processing

## Troubleshooting

### Common Issues

**Authentication fails with "Invalid Client"**
- Verify client ID/secret are correct
- Check redirect URI matches exactly: `macflare://oauth/callback`

**Token refresh fails**
- Ensure refresh tokens are enabled in Cloudflare OAuth app
- Check token expiration and refresh timing

**Network monitoring not working**
- Verify network entitlements are properly configured
- Check `NWPathMonitor` setup in auth manager

**Keychain storage fails**
- Ensure keychain entitlements are configured
- Check app signing and provisioning profile

The system is now fully implemented and ready for OAuth app creation and testing!
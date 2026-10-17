# Authentication verification — October 16, 2026

Reviewed PR #6 at `6feb2f2c0436838d856eea91ffea106c42779893` in an isolated worktree. No merge performed. The original checkout's signing edits were unchanged (before/after binary-diff SHA-256 `25a18c60de7894d5d7761072d901027d78199307050de5628b11c77fce0e5d74`). No Xcode project or tracked signing-entitlement edits were needed.

## Verified

- Xcode 27.0 (27A266a), arm64 macOS 27.0.1.
- Debug app compilation and hosted Swift Testing suite: **44 test methods / 54 cases passed**, zero failures, skips or runtime warnings.
- Release compilation with the project's existing Swift language settings, signing disabled.
- Real local socket callback test: loopback listener rejects a wrong state, accepts the matching callback, and cancels cleanly.
- Unique test-only Keychain round-trip and client isolation: removing development credentials preserves production and legacy entries. App-session tests inject an in-memory store and intercept URLSession requests.
- Actual app launch using ad-hoc signing and a temporary sandbox/network-only entitlement file. The missing-client error was checked before registration; the configured build was then used for the live checks below.
- Created **MacFlare Development**, private, with Code, Authorization Code + Refresh Token, None (PKCE), and required Account Settings Read permission. Public client ID: `f7c5d38ce7449d302ff8255b7394c99c`.
- The live Cloudflare client form rejected custom URI schemes. Registration and successful authorization confirmed `http://127.0.0.1:8976/oauth/callback`.
- The registered-client scope popup identified **`account-settings.read`** plus `offline_access`. The documentation's illustrative `account.read` was rejected with `invalid_scope`; source and tests now use the live identifier.

## Verified live authentication

Using the configured, sandboxed development build and real Cloudflare services:

1. Consent displayed Account Settings Read and Background Access; authorization returned through the local callback.
2. MacFlare loaded the Peter Allport account from Cloudflare. The account-list Refresh action succeeded.
3. **Development → Refresh Cloudflare Session** forced a real refresh grant and reloaded the account without errors.
4. Relaunch restored the refreshed session from Keychain and loaded the account again.
5. Sign Out removed the visible account and saved session. No revocation failure notice appeared after the request timeout window; the app treats only HTTP 2xx as confirmed revocation.
6. A second relaunch remained signed out.

These are live UI and application-flow observations, separate from compilation and stubbed tests. No token values were extracted for independent replay, so server rejection of the revoked token was not tested separately. Natural clock-expiry and failure/race scenarios are covered by the injected automated suite.

The suite covers callback validation and PKCE requests, account loading/pagination, expiration and missing refresh tokens, refresh-token rotation/coalescing, transient errors, actual Cloudflare invalid-token response semantics, permission failures, forced refresh, sign-out races, revocation, Keychain failures and recovery, and canceled restoration.

Cloudflare returns invalid bearer credentials as HTTP 403 with error 9109 and message “Invalid access token”. Error 9109 also appears for permission failures, so the implementation does not invalidate every 403/9109 response.

## Production and remaining limits

A separate **MacFlare Production** registration is prepared with private visibility, the same callback, PKCE grants, and minimal scopes. It has not been created. Public publication also requires publisher-domain verification and app metadata. No production client ID or production authentication is claimed.

An optional command-line Swift 6 override failed in the existing Inject dependency's shared mutable state. This probe forces the dependency's language mode too and does not establish that the new auth source fails Swift 6. Dependency modernization remains outside this authentication change. The project's current-settings Debug/Release builds passed.

The old template UI tests were not run; the focused suite is the `macflareTests` target. The live UI checks above were performed on the actual app. Signing overrides and the temporary entitlement file were used only for this isolated validation; distribution signing and notarization were not validated.

## Reproduce

```sh
xcodebuild -project macflare.xcodeproj -scheme macflare \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macflare-auth-review/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGN_ENTITLEMENTS= \
  CODE_SIGNING_ALLOWED=YES -only-testing:macflareTests test

xcodebuild -project macflare.xcodeproj -scheme macflare -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macflare-auth-review/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The tests use injected state, controlled task coordination, and isolated URLSession/URLProtocol responses. See [setup and primary sources](authentication.md).

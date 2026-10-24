# Authentication verification — October 16, 2026

Reviewed PR #6 at `6feb2f2c0436838d856eea91ffea106c42779893` in an isolated worktree. No merge performed. The original checkout's signing edits were unchanged, verified by comparing the before/after diff hashes. No Xcode project or tracked signing-entitlement edits were needed.

## Verified

- Xcode 27.0 (27A266a), arm64 macOS 27.0.1.
- Debug app compilation and hosted Swift Testing suite: **44 test methods / 54 cases passed**, zero failures, skips or runtime warnings.
- Release compilation with the project's existing Swift language settings, signing disabled.
- Real local socket callback test: loopback listener rejects a wrong state, accepts the matching callback, and cancels cleanly.
- Unique test-only Keychain round-trip and client isolation: removing development credentials preserves production and legacy entries. App-session tests inject an in-memory store and intercept URLSession requests.
- Actual app launch using ad-hoc signing and a temporary sandbox/network-only entitlement file. The missing-client error was checked before registration; the configured build was then used for the live checks below.
- Created **MacFlare Development**, private, with Code, Authorization Code + Refresh Token, None (PKCE), and required Account Settings Read permission. Its public client ID is in `Config/OAuthDevelopment.xcconfig`.
- The live Cloudflare client form rejected custom URI schemes. Registration and successful authorization confirmed `http://127.0.0.1:8976/oauth/callback`.
- The registered-client scope popup identified **`account-settings.read`** plus `offline_access`. The documentation's illustrative `account.read` was rejected with `invalid_scope`; source and tests now use the live identifier.

## Verified live authentication

Using the configured, sandboxed development build and real Cloudflare services:

1. Consent displayed Account Settings Read and Background Access; authorization returned through the local callback.
2. MacFlare loaded the authorized development account from Cloudflare. The account-list Refresh action succeeded.
3. **Development → Refresh Cloudflare Session** forced a real refresh grant and reloaded the account without errors.
4. Relaunch restored the refreshed session from Keychain and loaded the account again.
5. Sign Out removed the visible account and saved session. No revocation failure notice appeared after the request timeout window; the app treats only HTTP 2xx as confirmed revocation.
6. A second relaunch remained signed out.

These are live UI and application-flow observations, separate from compilation and stubbed tests. No token values were extracted for independent replay, so server rejection of the revoked token was not tested separately. Natural clock-expiry and failure/race scenarios are covered by the injected automated suite.

The suite covers callback validation and PKCE requests, account loading/pagination, expiration and missing refresh tokens, refresh-token rotation/coalescing, transient errors, actual Cloudflare invalid-token response semantics, permission failures, forced refresh, sign-out races, revocation, Keychain failures and recovery, and canceled restoration.

Cloudflare returns invalid bearer credentials as HTTP 403 with error 9109 and message “Invalid access token”. Error 9109 also appears for permission failures, so the implementation does not invalidate every 403/9109 response.

## Production and remaining limits

On October 17, 2026, the separate **MacFlare Production** registration was created with private visibility, the same loopback callback, Code response, Authorization Code + Refresh Token grants, None (PKCE), and `account-settings.read offline_access`. Its public client ID is recorded in `Config/OAuthProduction.xcconfig`; no client secret is used. Production live authentication was subsequently verified on October 23, as recorded below. Public publication still requires publisher-domain verification and app metadata.

Release compilation with `-xcconfig Config/OAuthProduction.xcconfig` and signing disabled passed. The built Info.plist contains the production client ID, distinct from development. This confirms build configuration only.

An optional command-line Swift 6 override failed in the existing Inject dependency's shared mutable state. This probe forces the dependency's language mode too and does not establish that the new auth source fails Swift 6. Dependency modernization remains outside this authentication change. The project's current-settings Debug/Release builds passed.

The old template UI tests were not run; the focused suite is the `macflareTests` target. The live UI checks above were performed on the actual app. Signing overrides and the temporary entitlement file were used only for this isolated validation; distribution signing and notarization were not validated.

## Live production verification — October 23, 2026

Tested the isolated authentication worktree at app-source revision `ec7ea31dc9711b2d798880299768a09a0ac6770b`, matching the open PR #6 head, with the local launcher correction described below. The original checkout and its signing diff were preserved. No merge performed.

The Debug app was built with `Config/OAuthProduction.xcconfig`, separate DerivedData, ad-hoc signing and a temporary sandbox/network-only entitlement file. The built `CloudflareClientID` was checked against the production configuration before consent. Debug was used to retain the command that forces a refresh grant; this was a live test of the production OAuth registration, not a distribution build.

1. Cloudflare consent identified **MacFlare Production** and displayed exactly Account Settings Read and Background Access.
2. Authorization returned through the loopback callback, and the actual app loaded the authorized account from Cloudflare.
3. The accounts-screen **Refresh** action reloaded accounts without an error.
4. **Development → Refresh Cloudflare Session** forced a real refresh grant, followed by successful account loading without a persistence notice.
5. After quitting and reopening the same app bundle, a new app process restored the saved session and loaded the account.
6. **Sign Out** cleared the visible account. No Keychain-deletion or revocation-failure notice appeared after 39 seconds, beyond the request's 15-second timeout. The app only accepts HTTP 2xx for revocation.
7. Another quit/reopen remained signed out. The same production-configured local build was left at the sign-in screen for manual testing.

No token values were read or replayed independently. Remote revocation evidence is the app's successful-response handling, not an independent replay test or browser logout. The existing 54-case automated result above was not rerun for this live check. Account names, account IDs, callback values, tokens and screenshots are excluded from this record and the repository.

The preflight exposed a launcher configuration bug: its development xcconfig overrode the documented command-line client-ID override. The script now selects exactly one source, in order: explicit client ID, `MACFLARE_OAUTH_CONFIG`, or the default development xcconfig. The production-configured build and embedded-ID check passed after the correction; shell syntax validation also passed.

After the Debug lifecycle check, a separate Release build using `Config/OAuthProduction.xcconfig` and the same temporary signing approach compiled and launched successfully. Its embedded client ID matched the production configuration, and the actual Release app restored the saved production session and displayed the account. The Debug-only refresh command was absent. Forced refresh and sign-out were verified in the production-configured Debug app above; they were not repeated in Release. This local Release run does not establish distribution signing or notarization.

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

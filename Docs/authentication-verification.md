# Authentication verification — October 16, 2026

Reviewed PR #6 at `6feb2f2c0436838d856eea91ffea106c42779893` in an isolated worktree. No merge performed. The original checkout's signing edits were unchanged (before/after binary-diff SHA-256 `25a18c60de7894d5d7761072d901027d78199307050de5628b11c77fce0e5d74`). No Xcode project or tracked signing-entitlement edits were needed.

## Verified

- Xcode 27.0 (27A266a), arm64 macOS 27.0.1.
- Debug app compilation and hosted Swift Testing suite: **43 test methods / 53 cases passed**, zero failures or skips.
- Release compilation with the project's existing Swift language settings, signing disabled.
- Real local socket callback test: loopback listener rejects a wrong state, accepts the matching callback, and cancels cleanly.
- Unique test-only Keychain item round-trip; app-session tests inject an in-memory store and intercept URLSession requests.
- Actual app launch using ad-hoc signing and a temporary sandbox/network-only entitlement file. The sign-in button visibly reports the missing OAuth client ID. This is a runtime check of the configuration boundary, not successful Cloudflare sign-in.
- The live Cloudflare client form rejected custom URI schemes and accepted the configured `http://127.0.0.1:8976/oauth/callback` URL. The form was prepared with Code, Authorization Code + Refresh Token, None (PKCE), and required Account Settings Read permission.

The suite covers callback validation and PKCE requests, account loading/pagination, expiration and missing refresh tokens, refresh-token rotation/coalescing, transient errors, actual Cloudflare invalid-token response semantics, permission failures, forced refresh, sign-out races, revocation, Keychain failures and recovery, and canceled restoration.

Cloudflare returns invalid bearer credentials as HTTP 403 with error 9109 and message “Invalid access token”. Error 9109 also appears for permission failures, so the implementation does not invalidate every 403/9109 response.

## Still pending

The account had no registered OAuth clients. Creation and consent are pending user confirmation. **Real Cloudflare consent, account loading, refresh, relaunch restoration, sign-out, and server revocation have not been verified.** The build has no registered client ID until that step completes.

An optional command-line Swift 6 override failed in the existing Inject dependency's shared mutable state. This probe forces the dependency's language mode too and does not establish that the new auth source fails Swift 6. Dependency modernization remains outside this authentication change. The project's current-settings Debug/Release builds passed.

The old template UI tests were not run; the focused suite is the `macflareTests` target. Real authenticated UI verification is pending registration.

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

Timespace references used read-only: `Model/Insiders/InsidersViewModel.swift` for observable/injected state and task coordination; `timespaceTests/NetworkServiceTests.swift` for URLSession/URLProtocol isolation. See [setup and primary sources](authentication.md).

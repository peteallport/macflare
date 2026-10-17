# Cloudflare authentication

MacFlare uses a public OAuth client (PKCE S256, no client secret) to read Cloudflare accounts. Credentials are stored in Keychain. The accounts screen can reload accounts and sign out; sign-out clears local state before attempting remote refresh-token revocation.

## Register a development client

Checked against Cloudflare's documentation and the Peter Allport account dashboard on October 16, 2026:

1. Open **Manage account → OAuth clients → Create client** in the account that owns MacFlare.
2. Use **Code** response type, **Authorization Code + Refresh Token** grants, and **None (PKCE)** token authentication.
3. Register **`http://127.0.0.1:8976/oauth/callback`** exactly. The dashboard rejected the PR's custom-scheme approach with “URL must start with http:// or https://”. It accepted the loopback URL in the form. Only successful client creation establishes saved registration.
4. Select **Account Settings → Read** only. MacFlare requests `account.read offline_access`; self-managed clients require dot-delimited API scopes. Wrangler's first-party colon-delimited scopes are not suitable. `offline_access` is managed by the refresh-token grant during registration.
5. Keep visibility **private** for development. Account members can authorize it. Public distribution is a separate, irreversible promotion requiring Cloudflare's domain-ownership and app-metadata checks.
6. Pass the returned public client ID through `CLOUDFLARE_CLIENT_ID` at build time. It is not a secret. Do not use Wrangler's client ID or put any access/refresh token in source or build settings.

The browser callback listener binds only `127.0.0.1`, opens the browser after binding, and exists only during sign-in. Port 8976 must be free. The callback, state, and PKCE verifier are validated before tokens are stored. Cancel in MacFlare closes the pending flow. A browser session at Cloudflare may remain logged in after MacFlare signs out.

## Build and run

Use `script/build_and_run.sh` or the Codex Run action. The script uses this worktree's own DerivedData and accepts additional Xcode build arguments after the mode:

```sh
CLOUDFLARE_CLIENT_ID='<registered-public-client-id>' ./script/build_and_run.sh --verify
```

Use a local signing configuration suitable for the existing project entitlements. Passing signing overrides to Xcode does not require editing `project.pbxproj`. Debug/Release compilation does not prove registration, consent, Keychain access, API permissions, refresh, or revocation.

## Verification

The automated suite injects browser authorization, token storage, a clock, and URLSession responses. It checks request bodies and observable state through expired restore, revoked tokens, transient failures, concurrent refresh, API rejection, persistence failures, and sign-out races. Stubbed responses establish app behavior only.

Before calling live authentication complete, verify the actual configured app:

- Browser consent returns to MacFlare and account names load from Cloudflare.
- Relaunch restores the session from Keychain.
- A real refresh grant succeeds and a subsequent account request works. In Debug builds, **Development → Refresh Cloudflare Session** requests this without waiting for expiry or modifying saved credentials.
- Sign-out clears the visible accounts and Keychain state; remote revocation succeeds or a visible notice explains the failure.
- Relaunch after sign-out stays signed out.

## Sources

- [Create an OAuth client](https://developers.cloudflare.com/fundamentals/oauth/create-an-oauth-client/)
- [OAuth client registration API and scope rules](https://developers.cloudflare.com/api/resources/iam/subresources/oauth_clients/methods/create/)
- [Authenticated scope catalog](https://developers.cloudflare.com/api/resources/iam/subresources/oauth_scopes/methods/list/)
- [Cloudflare OAuth integration endpoints](https://developers.cloudflare.com/fundamentals/oauth/integrate-with-cloudflare/)
- [Cloudflare refresh-token implementation](https://github.com/cloudflare/workers-sdk/blob/855812b79fcb8ee77cac5ab0b01ebc167741951d/packages/workers-auth/src/token-exchange.ts#L166-L233)
- [Cloudflare refresh-token revocation](https://github.com/cloudflare/workers-sdk/blob/855812b79fcb8ee77cac5ab0b01ebc167741951d/packages/workers-auth/src/flow.ts#L461-L470)
- [RFC 8252 native-app loopback redirects](https://www.rfc-editor.org/rfc/rfc8252#section-7.3)

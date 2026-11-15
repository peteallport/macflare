# macflare

Macflare is a native macOS prototype for Cloudflare power users. It implements PKCE sign-in, read-only account loading, session refresh and sign-out. See `Docs/authentication.md` for registered-client setup and the distinction between build checks and live authentication.

## Development baseline

- Read `CONTRIBUTING.md` for toolchain, build/test commands, signing, and dependency updates.
- Target macOS 14.0+ only. iOS and iPadOS are possible future work, not current supported destinations. Preserve existing capability declarations unless the maintainer requests changes, and distinguish declared permissions from implemented features.
- Use Swift 6 with complete strict concurrency checking for the app and tests. Keep UI state on `@MainActor`, use actors for shared mutable state, and pass `Sendable` values across isolation boundaries. Do not bypass diagnostics without a documented safety invariant.
- Use Swift Package Manager and commit intentional changes to `Package.resolved`. Inject is the sole third-party dependency and its integration is Debug-only.
- Use Swift Testing for unit tests and XCTest for UI tests. SwiftData tests use in-memory stores. Verify Debug tests, a Release build, and the hook regression checks for baseline changes.
- Keep personal signing edits intact and unstaged. The pre-commit hook validates the index without modifying files or staging changes; never assume it scrubs signing values.
- Run SwiftFormat in lint mode and SwiftLint with the checked-in configuration. Keep the hook read-only: never autoformat, auto-fix, or stage files during a commit. See `CONTRIBUTING.md` for tool versions and full checks.
- Preserve human source creators and actual dates. New source files use `Created by Peter C. Allport`.

- Base feature branches on `main`. Run public-content checks before committing and pushing; never print matched secrets or add blanket scanner exemptions. See `CONTRIBUTING.md` for scanner versions and required checks.

## Implementation

- Prefer structs for value types; use reference types where identity is required, including SwiftData models.
- Use typed `Decodable` models for API payloads when networking is implemented. Add `Hashable` when equality and collection semantics require it.
- Prefer accessible SwiftUI views. Use AppKit for missing macOS integration and wrap it narrowly for SwiftUI.
- Follow Apple's Human Interface Guidelines and Swift API Design Guidelines. Use clear names, focused functions, and documentation comments for public APIs or non-obvious behavior.
- Keep the README and contributor guide aligned with actual behavior. Do not describe planned authentication, CloudKit, push, or file features as implemented.
- Never log credentials or sensitive user data. Authentication credentials are stored in Keychain; iCloud sync is not configured.
- Use Context7 for current library/API documentation and primary-source web documentation when needed.

## License

Created by Peter C. Allport. Licensed under the [MIT License](LICENSE), which permits commercial use, modification, and redistribution. Preserve the copyright and permission notices in all copies or substantial portions of the software.

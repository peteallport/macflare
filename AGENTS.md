# macflare

Macflare is a native macOS prototype for Cloudflare power users. The welcome screen is implemented, but the login button is a placeholder; authentication and Cloudflare API operations are not implemented.

## Development baseline

- Read `CONTRIBUTING.md` for toolchain, build/test commands, signing, and dependency updates.
- Target macOS 14.0+ only. iOS and iPadOS are possible future work, not current supported destinations. Do not add platform settings or entitlements for unimplemented features.
- Use Swift 6 with complete strict concurrency checking for the app and tests. Keep UI state on `@MainActor`, use actors for shared mutable state, and pass `Sendable` values across isolation boundaries. Do not bypass diagnostics without a documented safety invariant.
- Use Swift Package Manager and commit intentional changes to `Package.resolved`. Inject is the sole third-party dependency and its integration is Debug-only.
- Use Swift Testing for unit tests and XCTest for UI tests. SwiftData tests use in-memory stores. Verify Debug tests, a Release build, and the hook regression checks for baseline changes.
- Keep personal signing edits intact and unstaged. The pre-commit hook validates the index without modifying files or staging changes; never assume it scrubs signing values.
- Run SwiftFormat in lint mode and SwiftLint with the checked-in configuration. Keep the hook read-only: never autoformat, auto-fix, or stage files during a commit. See `CONTRIBUTING.md` for tool versions and full checks.
- Preserve human source creators and actual dates. New source files use `Created by Peter C. Allport`.

## Implementation

- Prefer structs for value types; use reference types where identity is required, including SwiftData models.
- Use typed `Decodable` models for API payloads when networking is implemented. Add `Hashable` when equality and collection semantics require it.
- Prefer accessible SwiftUI views. Use AppKit for missing macOS integration and wrap it narrowly for SwiftUI.
- Follow Apple's Human Interface Guidelines and Swift API Design Guidelines. Use clear names, focused functions, and documentation comments for public APIs or non-obvious behavior.
- Keep the README and contributor guide aligned with actual behavior. Do not describe planned authentication, CloudKit, push, or file features as implemented.
- Never log credentials or sensitive user data. Use Keychain for credentials when authentication is implemented; iCloud sync is not configured.
- Use Context7 for current library/API documentation and primary-source web documentation when needed.

## License

Created by Peter C. Allport. Licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/); commercial use requires permission from the author. See `LICENSE`.

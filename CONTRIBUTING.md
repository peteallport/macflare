# Contributing

Thanks for your interest in improving `macflare`!

## Quick start

- Use Xcode 15.4+
- Build from CLI without signing:
  ```bash
  xcodebuild -project macflare.xcodeproj -scheme macflare -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
  ```

## Git hooks

- This repo uses a version-controlled pre-commit hook at `.githooks/pre-commit` to strip provisioning/team IDs and similar machine-specific code signing fields from `macflare.xcodeproj/project.pbxproj`.
- Enable hooks once per clone:
  ```bash
  git config core.hooksPath .githooks
  ```

## Pull requests

- Include a clear summary and testing steps (see PR template).
- Prefer small, focused changes.
- Add/adjust tests when possible.

## Code style

- Swift types use UpperCamelCase (e.g., `MacflareApp`).
- Keep functions small and compose with SwiftUI where possible.

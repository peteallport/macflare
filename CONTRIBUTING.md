# Contributing

Thanks for your interest in improving `macflare`!

## Quick start
- Use Xcode 15.4+
- Copy `macflare/Config/Development.example.xcconfig` to `macflare/Config/Development.xcconfig` and adjust values (see `macflare/Config/README.md`).
- Build from CLI without signing:
  ```bash
  xcodebuild -project macflare.xcodeproj -scheme macflare -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
  ```

## Pull requests
- Include a clear summary and testing steps (see PR template).
- Prefer small, focused changes.
- Add/adjust tests when possible.

## Code style
- Swift types use UpperCamelCase (e.g., `MacflareApp`).
- Keep functions small and compose with SwiftUI where possible.
# macflare

Power tools for Cloudflare natively on macOS. Coming very soon!

Macflare is open source and currently in active development.

## 🚀 Getting started

- The app and tests target **macOS 14.0+** on Mac. iOS and iPadOS are possible future work, not supported build destinations.
- Use **Xcode 27.0 (27A266a)**, matching the native Icon Composer 2 artwork, development validation, and CI; see [toolchain details](CONTRIBUTING.md#toolchain-and-platforms).
- Local ad-hoc builds and tests do not require an Apple Developer account.

```bash
git clone https://github.com/peteallport/macflare.git
cd macflare
git config core.hooksPath .githooks
./script/build_and_run.sh --verify
```

The script builds Debug, launches the app, and checks that its process remains running. It does not run tests. You can also open `macflare.xcodeproj` in Xcode and select the `macflare` scheme on **My Mac**. See [CONTRIBUTING.md](CONTRIBUTING.md) for test commands, Release builds, signing, and optional hot reload.

## 🛠️ Engineering baseline

- Swift 6 language mode and complete strict concurrency checking for the app and tests.
- The updated Default app icon uses native Icon Composer artwork and Xcode-generated compatibility images for older supported macOS releases. See [app icon maintenance](CONTRIBUTING.md#app-icon).
- Swift Package Manager with a tracked [`Package.resolved`](macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved); Inject 1.5.2 is the sole third-party dependency and its integration is Debug-only.
- In-memory SwiftData unit tests, a welcome-screen UI test, and regression tests for staged signing, SwiftFormat, and SwiftLint validation.
- The [macOS workflow](.github/workflows/macos.yml) runs Debug tests, a universal Release build, and Periphery. [Public-content checks](.github/workflows/quality.yml) and [CodeQL](.github/workflows/codeql.yml) run on pull requests and `main`.
- App Sandbox with incoming/outgoing network access and user-selected read-only file access. Existing CloudKit and push notification entitlements are retained, but their application features are not implemented. Hot reload permissions are limited to Debug.

Use short-lived feature branches and pull requests into `main`; there is no separate integration branch. See [quality and public-content policy](CONTRIBUTING.md#quality-and-public-content-policy).

## ❤️ Support macflare

- App Store distribution is planned.
- A project by [Peter C. Allport](https://peteallport.com), feel free to reach out!
- Consider [sponsoring macflare](https://github.com/sponsors/peteallport).

## 📄 License

This project is licensed under the [MIT License](LICENSE).

You’re free to use, modify, distribute, and sell the software, including for commercial purposes, provided you include the copyright and permission notices in all copies or substantial portions of the software.

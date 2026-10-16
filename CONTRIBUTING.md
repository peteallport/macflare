# Contributing to macflare

Macflare is a native macOS prototype. The welcome screen is implemented; the Cloudflare login button has no action yet. Keep documentation and capabilities aligned with working features.

## Toolchain and platforms

| Concern | Baseline |
| --- | --- |
| App and test deployment target | macOS 14.0 |
| Supported destination | Mac; no iOS, iPadOS, or Mac Catalyst target |
| Language | Swift 6 with complete strict concurrency checking |
| Project/compiler floor | Xcode 16+ for the project format and Swift 6; older versions are not continuously tested |
| Local validation toolchain | Xcode 27.0 (27A266a), Swift 6.4 |
| CI toolchain | Xcode 26.3 on GitHub-hosted `macos-15` |

The development Mac must meet the chosen Xcode version's host OS requirements. That requirement is separate from the app's macOS 14 deployment target. Builds on a newer host do not establish runtime coverage on macOS 14.

The [macOS 15 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md#xcode) lists `/Applications/Xcode_26.3.app`. CI selects it explicitly through `DEVELOPER_DIR`; update this pin deliberately when the hosted image changes. Local Xcode selection can also be overridden per command without changing the machine's default:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```

## Setup and verification

Clone the repository, then enable the staged signing validator once per clone:

```bash
git config core.hooksPath .githooks
```

Open `macflare.xcodeproj`, choose the `macflare` scheme and **My Mac**, or build and launch from the repository root:

```bash
./script/build_and_run.sh --verify
CONFIGURATION=Release ./script/build_and_run.sh --verify
```

The script defaults to Debug. `--verify` checks that the launched process remains running; it does not execute tests or establish that login works.

Use these commands to run the Debug unit/UI tests and build Release with ad-hoc signing. No Apple Developer account, provisioning profile, or signing certificate is needed:

```bash
xcodebuild test \
  -project macflare.xcodeproj -scheme macflare \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

xcodebuild build \
  -project macflare.xcodeproj -scheme macflare \
  -configuration Release -destination 'generic/platform=macOS' \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

python3 script/test-pre-commit.py
```

Unit tests use an in-memory SwiftData store and do not modify the app's persistent store. UI tests launch the actual app and verify the welcome screen and placeholder login control. The UI test host needs an active macOS graphical session; XCTest may request automation permission on a developer Mac.

The [CI workflow](.github/workflows/macos.yml) runs these checks in one fresh hosted Mac job, builds Release for both Apple Silicon and Intel, cancels superseded runs, checks that the dependency lockfile remains unchanged, and retains logs and `.xcresult` bundles for seven days after failures. It uses immutable commits for [checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) and [artifact upload](https://github.com/actions/upload-artifact/releases/tag/v7.0.2); the existing Dependabot configuration proposes action updates.

## Dependencies and hot reload

Use Swift Package Manager for third-party dependencies. Commit [`macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`](macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) whenever intentionally changing a package version. Normal builds use the resolved versions and must not silently update them. The current pin is [Inject 1.5.2](https://github.com/krzysztofzablocki/Inject/tree/1.5.2).

For an intentional dependency update, update the package in Xcode, review both the project requirement and lockfile diff, then run Debug tests and the Release build above. Do not delete the lockfile to fix a normal build.

Hot reload is optional. Install [InjectionIII](https://github.com/johnno1962/InjectionIII/releases), open this project in it, then run a Debug build and edit a SwiftUI view. Inject observation, injection modifiers, interposable linking, and hot reload entitlements are confined to Debug. A successful normal build does not verify a live InjectionIII session.

## Signing and capabilities

The checked-in project has generic bundle identifiers and empty developer team/signing identity settings. The commands above supply ad-hoc signing locally. Use an appropriate Apple signing identity and team only when preparing distribution; this repository does not include a distribution or notarization workflow.

Keep personal Xcode signing changes out of commits. Prefer command-line build setting overrides for local signing. If Xcode edits `project.pbxproj`, use selective staging to commit the intended shared changes while leaving the existing personal signing edits in the working tree. Avoid restoring the whole project file or staging it wholesale to address a hook failure.

The [pre-commit hook](.githooks/pre-commit) requires macOS `plutil` and Python 3 and validates the **staged contents only**. It rejects signing artifacts and nonempty developer team, provisioning profile, or signing identity settings, including conditional build settings. It also checks project syntax and distinct literal bundle identifiers across targets. It never rewrites the working tree, updates the index, or changes bundle identifiers. A rejection leaves both staged and unstaged changes intact so you can correct the staged configuration deliberately. Run `python3 script/test-pre-commit.py` after changing the hook.

The app uses App Sandbox and outgoing network access, including Debug's connection to InjectionIII. Debug alone disables library validation for injected code; Release retains library validation. Neither configuration permits incoming server connections. There is no current CloudKit/iCloud sync, push registration, or file import/export feature; add a capability only with its implementation and verification.

## Project structure and conventions

```text
macflare/
├── Model/             # SwiftData model
├── View/              # SwiftUI views and AppKit bridge
├── Assets.xcassets/   # App assets
└── macflareApp.swift  # App entry and persistence container
macflareTests/         # Swift Testing unit tests
macflareUITests/       # XCTest UI tests
script/               # Build/run and hook checks
```

- Use Swift Testing for new unit tests and XCTest for UI tests.
- Keep UI state on `@MainActor`; use actors for shared mutable state and `Sendable` for values crossing isolation boundaries. Do not disable concurrency checking to silence diagnostics.
- Prefer value types unless reference identity is required, as with SwiftData models. Decode API payloads into typed `Decodable` models when networking is added.
- Write accessible SwiftUI views and use AppKit for macOS integration where needed.
- Keep public API documentation and README behavior accurate. Preserve source creator names and dates.

## Pull requests and license

Include a clear summary, relevant verification results, and screenshots for user-visible changes using the [PR template](.github/pull_request_template.md). Prefer focused changes and open completed work ready for review. Merging requires the maintainer's approval.

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/): non-commercial use with attribution; commercial use requires permission from the author.

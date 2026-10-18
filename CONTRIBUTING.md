# Contributing to macflare

Macflare is a native macOS prototype. The welcome screen is implemented; the Cloudflare login button has no action yet. Keep documentation aligned with working features.

## Toolchain and platforms

| Concern | Baseline |
| --- | --- |
| App and test deployment target | macOS 14.0 |
| Supported destination | Mac; no iOS, iPadOS, or Mac Catalyst target |
| Language | Swift 6 with complete strict concurrency checking |
| Project/compiler floor | Xcode 16+ for the project format and Swift 6; older versions are not continuously tested |
| Local validation toolchain | Xcode 27.0 (27A266a), Swift 6.4 |
| CI toolchain | Xcode 27.0 (27A266a) on GitHub-hosted `xcode-27` |

The development Mac must meet the chosen Xcode version's host OS requirements. That requirement is separate from the app's macOS 14 deployment target. Builds on a newer host do not establish runtime coverage on macOS 14.

The [Xcode 27 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md#xcode) lists release Xcode 27.0 (27A266a) at `/Applications/Xcode_27.app`. GitHub currently labels the hosted image as preview; CI selects the release compiler explicitly through `DEVELOPER_DIR` and verifies its version and build number. Update this pin deliberately when the hosted image changes. Local Xcode selection can also be overridden per command without changing the machine's default:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```

## Setup and verification

Install [SwiftFormat 0.64.0](https://github.com/nicklockwood/SwiftFormat/releases/tag/0.64.0) and [SwiftLint 0.65.1](https://github.com/realm/SwiftLint/releases/tag/0.65.1), placing their executables on `PATH`. CI downloads these exact versions and verifies their SHA-256 digests before running them. Update tool versions and checksums together after checking the formatting and lint rules.

Clone the repository, then enable staged validation once per clone:

```bash
git config core.hooksPath .githooks
```

Open `macflare.xcodeproj`, choose the `macflare` scheme and **My Mac**, or build and launch from the repository root:

```bash
./script/build_and_run.sh --verify
CONFIGURATION=Release ./script/build_and_run.sh --verify
```

The script defaults to Debug and uses the ad-hoc entitlement copy described below. `--verify` checks that the launched process remains running; it does not execute tests or establish that login works.

Use these commands to run the Debug unit/UI tests and build Release with ad-hoc signing. The generated entitlement copies omit only push/iCloud claims that require provisioning, while retaining sandbox, file, network, and configuration-specific hot reload permissions. No Apple Developer account, provisioning profile, or signing certificate is needed for these checks; they do not validate provisioned cloud/push behavior:

```bash
python3 script/prepare_ad_hoc_entitlements.py Debug "$PWD/build/ad-hoc-Debug.entitlements"
xcodebuild test \
  -project macflare.xcodeproj -scheme macflare \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  MACFLARE_CODE_SIGN_ENTITLEMENTS="$PWD/build/ad-hoc-Debug.entitlements" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

python3 script/prepare_ad_hoc_entitlements.py Release "$PWD/build/ad-hoc-Release.entitlements"
xcodebuild build \
  -project macflare.xcodeproj -scheme macflare \
  -configuration Release -destination 'generic/platform=macOS' \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MACFLARE_CODE_SIGN_ENTITLEMENTS="$PWD/build/ad-hoc-Release.entitlements" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=

swiftformat macflare macflareTests macflareUITests --lint --cache ignore
swiftlint rules --config .swiftlint.yml > /dev/null
swiftlint lint --quiet --no-cache
python3 -B -u script/test-pre-commit.py
```

Unit tests use an in-memory SwiftData store and do not modify the app's persistent store. UI tests launch the actual app and verify the welcome screen and placeholder login control. The UI test host needs an active macOS graphical session; XCTest may request automation permission on a developer Mac.

The [CI workflow](.github/workflows/macos.yml) runs staged-validation regressions, formatting, lint, and build/test checks in one fresh hosted Mac job. It builds Release for both Apple Silicon and Intel, cancels superseded runs, checks that the dependency lockfile remains unchanged, and retains logs and `.xcresult` bundles for seven days after failures. It uses immutable commits for [checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) and [artifact upload](https://github.com/actions/upload-artifact/releases/tag/v7.0.2); the existing Dependabot configuration proposes action updates.

## Dependencies and hot reload

Use Swift Package Manager for third-party dependencies. Commit [`macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`](macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) whenever intentionally changing a package version. Normal builds use the resolved versions and must not silently update them. The current pin is [Inject 1.5.2](https://github.com/krzysztofzablocki/Inject/tree/1.5.2).

For an intentional dependency update, update the package in Xcode, review both the project requirement and lockfile diff, then run Debug tests and the Release build above. Do not delete the lockfile to fix a normal build.

Hot reload is optional. Install [InjectionIII](https://github.com/johnno1962/InjectionIII/releases), open this project in it, then run a Debug build and edit a SwiftUI view. Inject observation, injection modifiers, interposable linking, and hot reload entitlements are confined to Debug. A successful normal build does not verify a live InjectionIII session.

## Signing and capabilities

The checked-in project has generic bundle identifiers and empty developer team/signing identity settings. Normal Xcode builds retain the original entitlements and require an appropriate Apple development identity, team, and provisioning configuration for cloud/push capabilities. The commands above and CI explicitly override the app-only `MACFLARE_CODE_SIGN_ENTITLEMENTS` setting with a generated ad-hoc copy; test targets keep their own signing settings. The generator never changes the checked-in entitlement files. This repository does not include a distribution or notarization workflow.

Keep personal Xcode signing changes out of commits. Prefer command-line build setting overrides for local signing. If Xcode edits `project.pbxproj`, use selective staging to commit the intended shared changes while leaving the existing personal signing edits in the working tree. Avoid restoring the whole project file or staging it wholesale to address a hook failure.

The [pre-commit hook](.githooks/pre-commit) requires macOS `plutil`, Python 3, and the Swift tools above when staged Swift files need checking. It validates **staged contents only**, including staged formatter/linter configuration, so personal working edits do not affect the result. A staged change to a root or nested `.swiftformat` or `.swiftlint.yml` causes the hook to check all Swift sources in the index, even when no Swift file changed. It rejects signing artifacts and nonempty developer team, provisioning profile, or signing identity settings, including conditional build settings. It also checks project syntax and distinct literal bundle identifiers across targets.

SwiftFormat checks whitespace without rewriting files; SwiftLint checks a focused set of code issues. Formatting differences and lint errors block the commit; lint warnings remain visible without blocking. The hook never rewrites the working tree, updates the index, or changes bundle identifiers. A rejection leaves both staged and unstaged changes intact so you can correct the staged configuration deliberately. Run `python3 -B -u script/test-pre-commit.py` after changing the hook.

Both configurations retain the original App Sandbox, incoming/outgoing networking, user-selected read-only file access, CloudKit/iCloud, and development push notification entitlements. The iCloud container identifier list is empty, and SwiftData retains its default CloudKit selection. These declarations do not establish working sync, push registration, or file import/export features. Debug alone disables library validation for injected code; Release retains library validation. Preserve the existing capability settings unless the maintainer requests a change.

## Project structure and conventions

Repository instructions for coding agents live in [AGENTS.md](AGENTS.md).

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

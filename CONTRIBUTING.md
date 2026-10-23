# Contributing to macflare

Macflare is a native macOS prototype. The welcome screen is implemented; the Cloudflare login button has no action yet. Keep documentation aligned with working features.

## Toolchain and platforms

| Concern | Baseline |
| --- | --- |
| App and test deployment target | macOS 14.0 |
| Supported destination | Mac; no iOS, iPadOS, or Mac Catalyst target |
| Language | Swift 6 with complete strict concurrency checking |
| App build requirement | Xcode 27 for the Icon Composer 2 artwork; Xcode 16 is no longer sufficient |
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

The [CI workflow](.github/workflows/macos.yml) runs staged-validation regressions, formatting, lint, and build/test checks in one fresh hosted Mac job. It builds Release for both Apple Silicon and Intel, cancels superseded runs, checks that the dependency lockfile remains unchanged, and keeps raw logs and `.xcresult` bundles off uploaded artifacts. It uses immutable commits for [checkout](https://github.com/actions/checkout/releases/tag/v7.0.1) and [artifact upload](https://github.com/actions/upload-artifact/releases/tag/v7.0.2); the existing Dependabot configuration proposes action updates.

## App icon

[`macflare/macflare-S2.icon`](macflare/macflare-S2.icon) is the finalized revision 17 Icon Composer document, copied unchanged from the approved design delivery. It lives outside the asset catalog in the app's synchronized source folder, so Xcode includes it in the macOS target automatically. Both app configurations set `ASSETCATALOG_COMPILER_APPICON_NAME` to `macflare-S2`.

Preserve the document's appearance and material settings, its six embedded SVGs, and the rear cloud's straight lower edge. Every group has a watchOS-only translation of 24 points right and 24 points up; these saved design settings do not add a watchOS target or change the macOS composition. The app and tests remain macOS 14.0+ only.

Following [Apple's Icon Composer integration](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer), the asset compiler produces native icon stacks and flattened compatibility images in `Assets.car`, plus `macflare-S2.icns`. It also supplies `CFBundleIconName` and `CFBundleIconFile`; do not add competing manual Info.plist entries or an empty `AppIcon` asset set. The generated compatibility images provide the fallback for macOS 14 and 15. Their system-rendered margins, shadows, and materials can differ from an Icon Composer preview export.

Use Xcode 27 to build the approved Icon Composer 2 refractivity/specular settings. Supporting design exports are reference previews, not a second runtime icon source. When updating the icon, review the native document and generated fallback, build Debug and Release, and verify the running app's About panel and Dock icon. Inspect the built bundle's icon keys, `.icns`, and `Assets.car` renditions as well. A build on current macOS verifies packaging but does not establish runtime coverage on macOS 14 or 15.

## Dependencies and hot reload

Use Swift Package Manager for third-party dependencies. Commit [`macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`](macflare.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) whenever intentionally changing a package version. Normal builds use the resolved versions and must not silently update them. The current pin is [Inject 1.5.2](https://github.com/krzysztofzablocki/Inject/tree/1.5.2).

For an intentional dependency update, update the package in Xcode, review both the project requirement and lockfile diff, then run Debug tests and the Release build above. Do not delete the lockfile to fix a normal build.

Hot reload is optional. Install [InjectionIII](https://github.com/johnno1962/InjectionIII/releases), open this project in it, then run a Debug build and edit a SwiftUI view. Inject observation, injection modifiers, interposable linking, and hot reload entitlements are confined to Debug. A successful normal build does not verify a live InjectionIII session.

## Signing and capabilities

The checked-in project has generic bundle identifiers and empty developer team/signing identity settings. Normal Xcode builds retain the original entitlements and require an appropriate Apple development identity, team, and provisioning configuration for cloud/push capabilities. The commands above and CI explicitly override the app-only `MACFLARE_CODE_SIGN_ENTITLEMENTS` setting with a generated ad-hoc copy; test targets keep their own signing settings. The generator never changes the checked-in entitlement files. This repository does not include a distribution or notarization workflow.

Keep personal Xcode signing changes out of commits. Prefer command-line build setting overrides for local signing. If Xcode edits `project.pbxproj`, use selective staging to commit the intended shared changes while leaving the existing personal signing edits in the working tree. Avoid restoring the whole project file or staging it wholesale to address a hook failure.

The [pre-commit hook](.githooks/pre-commit) requires macOS `plutil`, Python 3, and the Swift tools above when staged Swift files need checking. It validates **staged contents only**, including staged formatter/linter configuration, so personal working edits do not affect the result. A staged change to a root or nested `.swiftformat` or `.swiftlint.yml` causes the hook to check all Swift sources in the index, even when no Swift file changed. It rejects signing artifacts and nonempty developer team, provisioning profile, or signing identity settings, including conditional build settings. It also checks project syntax, rejects bundle identifiers other than `com.example.macflare`, `com.example.macflareTests`, and `com.example.macflareUITests` (including conditional settings and variable references), and requires distinct identifiers across targets. Every target configuration must define its generic bundle identifier inline; inheriting it from an `.xcconfig` or project default is rejected. Keep contributor bundle IDs in unstaged local edits or command-line build overrides; selectively stage only the generic repository IDs. These checks never replace your local or staged values.

SwiftFormat checks whitespace without rewriting files; SwiftLint checks a focused set of code issues. Formatting differences and lint errors block the commit; lint warnings remain visible without blocking. The hook never rewrites the working tree, updates the index, or changes bundle identifiers. A rejection leaves both staged and unstaged changes intact so you can correct the staged configuration deliberately. Run `python3 -B -u script/test-pre-commit.py` after changing the hook.

Both configurations retain the original App Sandbox, incoming/outgoing networking, user-selected read-only file access, CloudKit/iCloud, and development push notification entitlements. The iCloud container identifier list is empty, and SwiftData retains its default CloudKit selection. These declarations do not establish working sync, push registration, or file import/export features. Debug alone disables library validation for injected code; Release retains library validation. Preserve the existing capability settings unless the maintainer requests a change.

## Project structure and conventions

Repository instructions for coding agents live in [AGENTS.md](AGENTS.md).

```text
macflare/
├── Model/             # SwiftData model
├── View/              # SwiftUI views and AppKit bridge
├── Assets.xcassets/   # App assets
├── macflare-S2.icon/   # Approved native app icon and embedded SVGs
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

This project is licensed under the [MIT License](LICENSE), which permits commercial use, modification, and redistribution. Include the copyright and permission notices in all copies or substantial portions of the software.

## Quality and public-content policy

Work on short-lived branches from `main` and open a pull request back to `main`.
The required checks apply to administrators too. Keep existing review requirements;
never bypass a failing check or merge without the maintainer's approval.

Install checksum-pinned validation tools in a directory on your PATH:

```bash
python3 script/install-quality-tools.py "$HOME/.local/bin" gitleaks periphery actionlint zizmor
export PATH="$HOME/.local/bin:$PATH"
git config core.hooksPath .githooks
```

The installer supports Apple Silicon macOS for all four tools and Linux x86-64 for
Gitleaks, actionlint, and zizmor. SwiftFormat and SwiftLint use the pins above.
The existing hooks path enables both pre-commit and pre-push; no global Git setting
is needed. Hooks can be bypassed or absent in another clone, so GitHub push
protection and required CI are additional layers, not substitutes.

- **Before commits:** Gitleaks scans the active index, alongside privacy checks for
  local home paths, literal Cloudflare account/zone IDs, private-key headers, signing
  material, private environment/configuration files, and `private/`, `captures/`, or
  `account-exports/` directories. These are explicit patterns, not a guarantee that
  all personal or business information can be recognized. Review the staged diff.
- **Before pushes and in CI:** scan the full ancestry of each pushed ref (CI: the checked-out revision) with
  Gitleaks and the private-content rules, including
  sensitive files added and later removed. All findings block; inline allow comments and
  repository/environment Gitleaks allowlists cannot suppress the scan. Diagnostics
  show file/rule only, never matched values. No blanket secret baseline is allowed.
- **Public information:** preserve creator attribution, intentional public links,
  generic examples, and public OAuth client IDs. Use synthetic account data in tests.
  Never commit real API responses, account exports, session tokens, private keys,
  provisioning files, screenshots containing private data, or local configuration.
  Images and arbitrary private prose still need human review.
- **Unused Swift:** Periphery 3.8.0 runs strictly against the `macflare` scheme,
  including tests. Remove verified dead code; retain genuine framework entry points
  only with a narrow documented annotation. Do not add a blanket findings baseline.
- **Workflow safety:** actionlint 1.7.12 and zizmor 1.31.1 validate Actions. Actions
  use full commit pins, downloads use SHA-256 checks, and PR jobs receive no repository
  secrets. Gitleaks is pinned to 8.30.1. Update `script/quality-tools.json` deliberately,
  review upstream release notes, and rerun checks when updating any tool.
- **Security analysis:** CodeQL runs on macOS 26 with Xcode 26.6 (17F113),
  separately from the Xcode 27 build/test/Periphery job. GitHub documents an
  [Xcode 27 / Swift 6.4 tracing incompatibility](https://github.com/github/codeql/issues/22742).
  This scans the source using the older supported toolchain; it does not establish
  analysis of an Xcode 27 binary or future Swift 6.4-only source. Its analysis-only
  build excludes the Icon Composer 2 document and clears the app-icon name because
  the artwork requires Xcode 27; the main macOS job still compiles the full icon
  in Debug and Release. Revisit the pin when upstream adds support. CodeQL uses a
  clean, single-architecture Swift build
  with signing and compiler caches disabled. Compilation/extraction failures are
  failures, not clean security results. The security-extended suite reports findings;
  branch protection blocks high/critical security findings and error-level results.
- **Dependencies:** Dependabot updates Actions weekly. This is an Xcode-managed SPM
  project without a `Package.swift`, so do not add an inapplicable Swift Dependabot
  entry. Review Inject releases monthly, update the Xcode requirement and tracked
  lockfile together, and run Debug tests and the universal Release build. Review
  scanner/compiler compatibility at the same time.

Run the checks locally:

```bash
python3 script/check-public-content.py --history
python3 -B -u script/test-public-content.py
.githooks/pre-commit --all
python3 -B -u script/test-pre-commit.py
periphery scan --config .periphery.yml --clean-build -- CODE_SIGNING_ALLOWED=NO -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile
actionlint
zizmor --offline --no-progress .github/workflows
```

If a real credential is exposed, revoke/rotate it first. Do not paste it into a PR,
issue, log, or report. Report only the filename and credential category privately;
history rewriting requires a separately coordinated decision. A deleted file does
not erase earlier commits. Public PR prose and media require the same review as code.

`--history` checks HEAD's complete ancestry by default; `--revision <ref>` selects
another history. Pre-push validates every non-deleted ref supplied by Git, including
branches other than the checked-out branch. `--all-history` is an explicit audit of
all local refs, including retired development branches; those old refs may retain
historical local configuration. Clean promotion preserves final code changes without
importing that ancestry into main. It does not erase old GitHub PRs, forks, or caches.

#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
case "$mode" in
  run|--debug|--logs|--verify) ;;
  *) echo "Usage: $0 [--debug|--logs|--verify]" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [--debug|--logs|--verify]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-Debug}"
case "$configuration" in
  Debug|Release) ;;
  *) echo "CONFIGURATION must be Debug or Release." >&2; exit 2 ;;
esac
derived_data="$repo_root/build/DerivedData"
app_bundle="$derived_data/Build/Products/$configuration/macflare.app"
app_binary="$app_bundle/Contents/MacOS/macflare"
ad_hoc_entitlements="$repo_root/build/ad-hoc-$configuration.entitlements"
python3 "$repo_root/script/prepare_ad_hoc_entitlements.py" "$configuration" "$ad_hoc_entitlements"

# Stop only the app built by this worktree, leaving other checkouts alone.
app_pids() {
  local pid
  for pid in $(pgrep -x macflare || true); do
    if [[ "$(ps -p "$pid" -o comm=)" == "$app_binary" ]]; then
      printf '%s\n' "$pid"
    fi
  done
}
for pid in $(app_pids); do
  kill "$pid"
done

xcodebuild -project "$repo_root/macflare.xcodeproj" -scheme macflare \
  -configuration "$configuration" -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$derived_data" -clonedSourcePackagesDirPath "$repo_root/build/SourcePackages" \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= \
  MACFLARE_CODE_SIGN_ENTITLEMENTS="$ad_hoc_entitlements" build

case "$mode" in
  --debug)
    xcrun lldb -- "$app_binary"
    ;;
  --logs)
    open -n "$app_bundle"
    /usr/bin/log stream --info --style compact --predicate 'process == "macflare"'
    ;;
  --verify)
    open -n "$app_bundle"
    sleep 2
    if [[ -z "$(app_pids)" ]]; then
      echo "Macflare did not remain running after launch." >&2
      exit 1
    fi
    echo "Macflare is running from $app_bundle"
    ;;
  run)
    open -n "$app_bundle"
    ;;
esac

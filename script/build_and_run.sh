#!/usr/bin/env bash
# Created by Peter C. Allport on 10/16/26.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify) ;; *) echo "usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;; esac
DERIVED_DATA="${MACFLARE_DERIVED_DATA:-$ROOT_DIR/build/DerivedData}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/macflare.app"
# Stop only this worktree's app, preserving apps launched from other checkouts.
pkill -f "^$APP_BUNDLE/Contents/MacOS/macflare" 2>/dev/null || true
cd "$ROOT_DIR"
xcodebuild -project macflare.xcodeproj -scheme macflare -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
  "CLOUDFLARE_CLIENT_ID=${CLOUDFLARE_CLIENT_ID:-}" "${@:2}" build
case "$MODE" in
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/macflare" ;;
  --logs) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "macflare"' ;;
  --telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.example.macflare"' ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -f "^$APP_BUNDLE/Contents/MacOS/macflare" >/dev/null ;;
  *) open -n "$APP_BUNDLE" ;;
esac

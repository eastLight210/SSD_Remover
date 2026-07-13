#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PREVIEW_STATE="${2:-volume-list}"
APP_NAME="SSD_Remover"
BUNDLE_ID="com.honeybadger210.SSD-Remover"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.tmp/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/SSD_Remover.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_preview() {
  /usr/bin/open -n "$APP_BUNDLE" --args \
    -NSSSDRemoverUIPreview YES \
    -NSSSDRemoverPreviewState "$PREVIEW_STATE" \
    -AppleInterfaceStyle Light
}

case "$MODE" in
  run)
    open_app
    ;;
  --preview|preview)
    open_preview
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--preview|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

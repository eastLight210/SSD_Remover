#!/usr/bin/env bash
# Build a Developer ID signed, notarized, stapled SSD_Remover.zip from a git tag,
# and optionally publish it to the matching GitHub release.
#
# One-time setup (stores an app-specific password in the Keychain):
#   xcrun notarytool store-credentials notary --apple-id "<apple-id>" --team-id Z2JK3QC3SS
set -euo pipefail

APP_NAME="SSD_Remover"
TEAM_ID="Z2JK3QC3SS"
SIGN_IDENTITY="Developer ID Application: Donghyeok Kim ($TEAM_ID)"

usage() {
  cat >&2 <<EOF
usage: $0 <tag> [--publish] [--notes FILE] [--profile NAME]

  <tag>           existing git tag to build (e.g. v1.1.0)
  --publish       upload to the GitHub release <tag> (created if missing,
                  asset replaced if it exists)
  --notes FILE    release notes (default: auto-generated when creating)
  --profile NAME  notarytool keychain profile (default: notary)
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
TAG="$1"; shift
PUBLISH=0
NOTES_FILE=""
PROFILE="notary"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --notes) NOTES_FILE="${2:?}"; shift ;;
    --profile) PROFILE="${2:?}"; shift ;;
    *) usage ;;
  esac
  shift
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.tmp/release/$TAG"
DERIVED_DATA="$OUT_DIR/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
ZIP_PATH="$OUT_DIR/$APP_NAME.zip"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

step "Preflight"
git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG not found"
[[ "$(security find-identity -v -p codesigning)" == *"$SIGN_IDENTITY"* ]] || die "signing identity not found: $SIGN_IDENTITY"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$PROFILE' not usable; see setup comment at top of $0"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || die "notes file not found: $NOTES_FILE"
if [[ $PUBLISH -eq 1 ]]; then
  command -v gh >/dev/null || die "gh CLI required for --publish"
fi

# Info.plist hardcodes the version, so make sure it matches the tag (v1.1.0 ~ 1.1).
normalize() { local v="${1#v}"; while [[ "$v" == *.0 ]]; do v="${v%.0}"; done; echo "$v"; }
PLIST_VERSION="$(git -C "$ROOT_DIR" show "$TAG:SSD_Remover/Resources/Info.plist" \
  | plutil -extract CFBundleShortVersionString raw -o - -)"
[[ "$(normalize "$TAG")" == "$(normalize "$PLIST_VERSION")" ]] \
  || die "tag $TAG does not match CFBundleShortVersionString $PLIST_VERSION"

WORKTREE="$(mktemp -d)/src"
cleanup() { git -C "$ROOT_DIR" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git -C "$ROOT_DIR" worktree add --detach "$WORKTREE" "$TAG" >/dev/null
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

step "Build $TAG (Release, Developer ID)"
xcodebuild \
  -project "$WORKTREE/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet \
  build

step "Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
[[ "$(codesign -dvv "$APP_BUNDLE" 2>&1)" == *"(runtime)"* ]] || die "hardened runtime not enabled"

step "Notarize"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait 2>&1)" || true
echo "$SUBMIT_OUTPUT"
if ! grep -q "status: Accepted" <<<"$SUBMIT_OUTPUT"; then
  SUBMISSION_ID="$(awk '/^  id:/ { print $2; exit }' <<<"$SUBMIT_OUTPUT")"
  [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" || true
  die "notarization failed"
fi

step "Staple and repackage"
xcrun stapler staple "$APP_BUNDLE"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Check the zip as a user would receive it.
CHECK_DIR="$(mktemp -d)"
ditto -x -k "$ZIP_PATH" "$CHECK_DIR"
spctl --assess --type exec --verbose=2 "$CHECK_DIR/$APP_NAME.app"
xcrun stapler validate "$CHECK_DIR/$APP_NAME.app"
rm -rf "$CHECK_DIR"

if [[ $PUBLISH -eq 1 ]]; then
  step "Publish to GitHub release $TAG"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP_PATH" --clobber
    [[ -n "$NOTES_FILE" ]] && gh release edit "$TAG" --notes-file "$NOTES_FILE" >/dev/null
  elif [[ -n "$NOTES_FILE" ]]; then
    gh release create "$TAG" "$ZIP_PATH" --title "$TAG" --notes-file "$NOTES_FILE"
  else
    gh release create "$TAG" "$ZIP_PATH" --title "$TAG" --generate-notes
  fi
  gh release view "$TAG" --json url -q .url
fi

step "Done: $ZIP_PATH"

#!/usr/bin/env bash
# Build a Developer ID signed, notarized, stapled SSD_Remover.zip and
# SSD_Remover.dmg from a git tag, write the Sparkle appcast.xml for the zip, and
# optionally publish all three to the matching GitHub release. The dmg is for
# first installs (the landing page links to it); Sparkle updates use the zip. The app's SUFeedURL points at
# releases/latest/download/appcast.xml, so publishing is what ships the update.
#
# One-time setup (stores an app-specific password in the Keychain):
#   xcrun notarytool store-credentials notary --apple-id "<apple-id>" --team-id Z2JK3QC3SS
# Sparkle's EdDSA private key must also be in the login Keychain (created by
# Sparkle's generate_keys; back it up with `generate_keys -x <file>`).
set -euo pipefail

APP_NAME="SSD_Remover"
REPO_URL="https://github.com/eastLight210/SSD_Remover"
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
DMG_PATH="$OUT_DIR/$APP_NAME.dmg"
APPCAST_PATH="$OUT_DIR/appcast.xml"
SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"

step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
notarize() {
  local output submission_id
  output="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)" || true
  echo "$output"
  if ! grep -q "status: Accepted" <<<"$output"; then
    submission_id="$(awk '/^  id:/ { print $2; exit }' <<<"$output")"
    [[ -n "$submission_id" ]] && xcrun notarytool log "$submission_id" --keychain-profile "$PROFILE" || true
    die "notarization failed: $1"
  fi
}

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
TAG_PLIST="$(git -C "$ROOT_DIR" show "$TAG:SSD_Remover/Resources/Info.plist")"
plist_value() { plutil -extract "$1" raw -o - - <<<"$TAG_PLIST"; }
PLIST_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value CFBundleVersion)"
MIN_SYSTEM_VERSION="$(git -C "$ROOT_DIR" show "$TAG:project.yml" \
  | awk '/MACOSX_DEPLOYMENT_TARGET:/ { gsub(/"/, "", $2); print $2; exit }')"
[[ -n "$MIN_SYSTEM_VERSION" ]] || die "MACOSX_DEPLOYMENT_TARGET not found in project.yml at $TAG"
[[ "$(normalize "$TAG")" == "$(normalize "$PLIST_VERSION")" ]] \
  || die "tag $TAG does not match CFBundleShortVersionString $PLIST_VERSION"
PUBLIC_ED_KEY="$(plist_value SUPublicEDKey 2>/dev/null)" \
  || die "$TAG has no SUPublicEDKey in Info.plist; Sparkle updates need it"

# Sparkle compares CFBundleVersion, so a release that doesn't bump it is never offered.
PREVIOUS_TAG="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
if [[ -n "$PREVIOUS_TAG" ]]; then
  PREVIOUS_BUILD="$(git -C "$ROOT_DIR" show "$PREVIOUS_TAG:SSD_Remover/Resources/Info.plist" \
    | plutil -extract CFBundleVersion raw -o - -)"
  (( BUILD_VERSION > PREVIOUS_BUILD )) \
    || die "CFBundleVersion $BUILD_VERSION must be greater than $PREVIOUS_TAG's $PREVIOUS_BUILD"
fi
# Re-publishing the same tag is fine; a new tag must raise the published build number.
if [[ $PUBLISH -eq 1 ]] \
  && PUBLISHED_APPCAST="$(curl -fsSL "$REPO_URL/releases/latest/download/appcast.xml" 2>/dev/null)" \
  && [[ "$PUBLISHED_APPCAST" != *"/releases/download/$TAG/"* ]]; then
  PUBLISHED_BUILD="$(sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p' <<<"$PUBLISHED_APPCAST" | head -1)"
  [[ -z "$PUBLISHED_BUILD" ]] || (( BUILD_VERSION > PUBLISHED_BUILD )) \
    || die "CFBundleVersion $BUILD_VERSION must be greater than the published build $PUBLISHED_BUILD"
fi

WORKTREE="$(mktemp -d)/src"
cleanup() { git -C "$ROOT_DIR" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git -C "$ROOT_DIR" worktree add --detach "$WORKTREE" "$TAG" >/dev/null
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

step "Check Sparkle signing key"
xcodebuild -resolvePackageDependencies \
  -project "$WORKTREE/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet
[[ -x "$SPARKLE_BIN/sign_update" ]] || die "Sparkle tools not found in $SPARKLE_BIN"
KEYCHAIN_ED_KEY="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" \
  || die "no Sparkle EdDSA key in the Keychain; run $SPARKLE_BIN/generate_keys (or import a backup with -f)"
[[ "$KEYCHAIN_ED_KEY" == "$PUBLIC_ED_KEY" ]] \
  || die "Keychain Sparkle key ($KEYCHAIN_ED_KEY) does not match SUPublicEDKey ($PUBLIC_ED_KEY)"

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

# Xcode signs Sparkle.framework on copy but leaves its nested helpers ad-hoc
# signed, which notarization rejects. Re-sign inside-out, then the app itself.
step "Sign Sparkle helpers"
SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
for item in \
  "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" \
  "$SPARKLE_FRAMEWORK/Versions/B/Updater.app" \
  "$SPARKLE_FRAMEWORK"; do
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --preserve-metadata=entitlements "$item"
done
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
  --preserve-metadata=entitlements,requirements,flags "$APP_BUNDLE"

step "Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
[[ "$(codesign -dvv "$APP_BUNDLE" 2>&1)" == *"(runtime)"* ]] || die "hardened runtime not enabled"
while IFS= read -r -d '' code; do
  [[ "$(codesign -dvv "$code" 2>&1)" == *"Authority=Developer ID Application"* ]] \
    || die "not Developer ID signed: ${code#"$APP_BUNDLE/"}"
done < <(find "$APP_BUNDLE/Contents/Frameworks" \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name Autoupdate \) -print0)

step "Notarize"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
notarize "$ZIP_PATH"

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

# Drag-to-install disk image with an Applications shortcut, containing the
# already stapled app. The dmg itself is signed, notarized, and stapled too.
step "Build and notarize dmg"
DMG_STAGING="$(mktemp -d)"
ditto "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "SSD Remover" -srcfolder "$DMG_STAGING" -fs HFS+ -format UDZO -ov "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
notarize "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

step "Sign update for Sparkle"
# Prints: sparkle:edSignature="..." length="..."
ED_SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")"
[[ "$ED_SIGNATURE_ATTRS" == *'sparkle:edSignature='* ]] || die "sign_update failed: $ED_SIGNATURE_ATTRS"

# Single-item appcast; each release replaces the previous one at releases/latest.
write_appcast() {
  local notes="$1"
  local description=""
  if [[ -n "$notes" ]]; then
    description="      <description sparkle:format=\"plain-text\"><![CDATA[${notes//]]>/]]]]><![CDATA[>}]]></description>"
  fi
  cat >"$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SSD Remover</title>
    <link>$REPO_URL</link>
    <item>
      <title>$PLIST_VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$PLIST_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$REPO_URL/releases</sparkle:fullReleaseNotesLink>
$description
      <enclosure url="$REPO_URL/releases/download/$TAG/$APP_NAME.zip" type="application/octet-stream" $ED_SIGNATURE_ATTRS />
    </item>
  </channel>
</rss>
XML
  xmllint --noout "$APPCAST_PATH" || die "generated appcast.xml is not valid XML"
}
write_appcast "$([[ -n "$NOTES_FILE" ]] && cat "$NOTES_FILE")"

if [[ $PUBLISH -eq 1 ]]; then
  step "Publish to GitHub release $TAG"
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$ZIP_PATH" "$DMG_PATH" --clobber
    [[ -n "$NOTES_FILE" ]] && gh release edit "$TAG" --notes-file "$NOTES_FILE" >/dev/null
  elif [[ -n "$NOTES_FILE" ]]; then
    gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" --title "$TAG" --notes-file "$NOTES_FILE"
  else
    gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" --title "$TAG" --generate-notes
  fi
  # Embed the final release notes (possibly auto-generated) in the update alert.
  write_appcast "$(gh release view "$TAG" --json body -q .body)"
  gh release upload "$TAG" "$APPCAST_PATH" --clobber
  gh release view "$TAG" --json url -q .url
fi

step "Done: $ZIP_PATH, $DMG_PATH, $APPCAST_PATH"

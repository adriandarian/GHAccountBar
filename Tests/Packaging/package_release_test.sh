#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD_NUMBER="${2:-1}"
APP_NAME="GHAccountBar"
RESOURCE_PATH="Contents/Resources/MenuBarIcon.png"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGER="$ROOT_DIR/script/package_release.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ZIP_NAME="$APP_NAME-v$VERSION-arm64.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
CHECKSUM_PATH="$ZIP_PATH.sha256"
EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ghaccountbar-release-test.XXXXXX")"

cleanup() {
  rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

fail() {
  echo "package_release_test: $*" >&2
  exit 1
}

if "$PACKAGER" invalid-version "$BUILD_NUMBER" >/dev/null 2>&1; then
  fail "packager accepted an invalid semantic version"
fi

if "$PACKAGER" "$VERSION" 0 >/dev/null 2>&1; then
  fail "packager accepted a non-positive build number"
fi

"$PACKAGER" "$VERSION" "$BUILD_NUMBER"

test -d "$APP_BUNDLE" || fail "app bundle is missing"
test -x "$EXECUTABLE" || fail "app executable is missing"
test -f "$APP_BUNDLE/$RESOURCE_PATH" || fail "menu bar icon resource is missing"
test -f "$ZIP_PATH" || fail "release ZIP is missing"
test -f "$CHECKSUM_PATH" || fail "release checksum is missing"

plutil -lint "$INFO_PLIST" >/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")" = "com.adriandarian.GHAccountBar" || fail "bundle identifier is incorrect"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")" = "$VERSION" || fail "release version is incorrect"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")" = "$BUILD_NUMBER" || fail "build number is incorrect"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$INFO_PLIST")" = "14.0" || fail "minimum macOS version is incorrect"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$INFO_PLIST")" = "true" || fail "app is not configured as a menu bar utility"

test "$(lipo -archs "$EXECUTABLE")" = "arm64" || fail "release executable is not arm64-only"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"
test -x "$EXTRACT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" || fail "ZIP does not contain the app executable"
test -f "$EXTRACT_DIR/$APP_NAME.app/$RESOURCE_PATH" || fail "ZIP does not contain the menu bar icon resource"

(cd "$DIST_DIR" && shasum -a 256 -c "$ZIP_NAME.sha256")

echo "release package verified"

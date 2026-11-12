#!/usr/bin/env bash
# Builds build/Offshoot.app.
#
#   scripts/build-app.sh              native arch, ad-hoc signed
#   scripts/build-app.sh --install    also copy to ~/Applications and launch
#   scripts/build-app.sh --release    universal binary + build/Offshoot-<version>.zip
#
# VERSION (default: latest git tag, else 0.0.0-dev) sets the bundle version.
# SIGN_IDENTITY signs with a Developer ID instead of ad-hoc (hardened runtime enabled).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"

ARCH_FLAGS=()
if [ "$MODE" = "--release" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Offshoot"

APP=build/Offshoot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Offshoot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"

case "$MODE" in
--install)
    pkill -x Offshoot 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Offshoot.app"
    cp -R "$APP" "$HOME/Applications/Offshoot.app"
    open "$HOME/Applications/Offshoot.app"
    echo "Installed to ~/Applications/Offshoot.app"
    ;;
--release)
    ZIP="build/Offshoot-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
    ;;
esac

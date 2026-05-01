#!/usr/bin/env bash
#
# Build Ghost as a real macOS .app bundle and install it to ~/Applications.
#
# Usage:
#   ./scripts/build_app.sh [--reset-permissions] [path/to/icon.png]
#
# Flags:
#   --reset-permissions, -r
#       After install, wipe the existing Accessibility grant for Ghost
#       (tccutil reset) so macOS re-prompts on next launch. Use this when
#       upgrading across a change in event-tap level (e.g. the move from
#       .cgSessionEventTap to .cghidEventTap), or when the grant seems
#       stuck. Routine rebuilds do NOT need this — the stable cert from
#       setup_dev_cert.sh keeps the existing grant valid.
#
# Steps:
#   1. Compile the SPM target in release mode.
#   2. Generate AppIcon.icns from the supplied PNG. If no path is given,
#      use the repo's logo.png at the project root.
#   3. Construct Ghost.app/Contents/{Info.plist, MacOS/Ghost,
#      Resources/AppIcon.icns}.
#   4. Sign with a stable self-signed cert if one is in the login keychain
#      (run scripts/setup_dev_cert.sh once to install one), otherwise
#      ad-hoc sign with a warning.
#   5. Install to ~/Applications/Ghost.app, replacing any prior copy.
#   6. Optionally reset the Accessibility grant (--reset-permissions).
#
# Note: macOS Accessibility permission is bound to the binary's code-
# signing "designated requirement". Ad-hoc signatures change every build
# (TCC sees each rebuild as a different app and resets the grant). The
# stable cert from setup_dev_cert.sh keeps the DR constant across rebuilds
# so the grant persists.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RESET_PERMISSIONS=0
ICON_SRC=""
for arg in "$@"; do
    case "$arg" in
        --reset-permissions|-r)
            RESET_PERMISSIONS=1
            ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        -*)
            echo "error: unknown flag '$arg'" >&2
            exit 1
            ;;
        *)
            ICON_SRC="$arg"
            ;;
    esac
done
ICON_SRC="${ICON_SRC:-$PKG_DIR/logo.png}"

APP_NAME="Ghost"
BUNDLE_ID="com.textutility.ghost"
SHORT_VERSION="0.1"
BUILD_VERSION="1"
MIN_MACOS="14.0"

INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
WORK_DIR="$(mktemp -d -t ghost-app-build)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -f "$ICON_SRC" ]]; then
    echo "error: icon source not found: $ICON_SRC" >&2
    echo "  pass a path as the first argument, or place a logo.png at the repo root." >&2
    exit 1
fi

echo "==> Building release binary"
cd "$PKG_DIR"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Generating AppIcon.icns from $ICON_SRC"
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for SPEC in \
    "16    icon_16x16.png" \
    "32    icon_16x16@2x.png" \
    "32    icon_32x32.png" \
    "64    icon_32x32@2x.png" \
    "128   icon_128x128.png" \
    "256   icon_128x128@2x.png" \
    "256   icon_256x256.png" \
    "512   icon_256x256@2x.png" \
    "512   icon_512x512.png" \
    "1024  icon_512x512@2x.png"
do
    SIZE="${SPEC%% *}"
    NAME="${SPEC##* }"
    sips -z "$SIZE" "$SIZE" "$ICON_SRC" --out "$ICONSET/$NAME" >/dev/null
done
ICNS="$WORK_DIR/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> Constructing $APP_NAME.app"
STAGED="$WORK_DIR/$APP_NAME.app"
mkdir -p "$STAGED/Contents/MacOS" "$STAGED/Contents/Resources"
cp "$BIN_PATH" "$STAGED/Contents/MacOS/$APP_NAME"
cp "$ICNS" "$STAGED/Contents/Resources/AppIcon.icns"

cat > "$STAGED/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_MACOS</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Ghost reads keystrokes from the focused app to track your progress through the saved passage. It only observes; it never injects or modifies events.</string>
</dict>
</plist>
PLIST

echo "==> Signing"
# Prefer the stable self-signed cert created by ./scripts/setup_dev_cert.sh.
# Its designated requirement stays the same across rebuilds, so the user's
# Accessibility grant survives (TCC keys grants by DR). Without the cert
# we fall back to ad-hoc, which TCC treats as a different binary on every
# rebuild, forcing the user to re-grant Accessibility each time.
SIGN_IDENTITY="Ghost Local Dev"
MATCH_COUNT=$(security find-identity -p codesigning 2>/dev/null \
    | grep -c "\"$SIGN_IDENTITY\"" || true)
if [[ "$MATCH_COUNT" -gt 1 ]]; then
    echo "  ERROR: $MATCH_COUNT certs named '$SIGN_IDENTITY' in your keychain (codesign would be ambiguous)." >&2
    echo "  list:    security find-identity -p codesigning | grep '$SIGN_IDENTITY'" >&2
    echo "  delete:  security delete-identity -Z <SHA1> ~/Library/Keychains/login.keychain-db" >&2
    exit 1
fi
if [[ "$MATCH_COUNT" -eq 1 ]]; then
    echo "  using stable identity: $SIGN_IDENTITY (Accessibility grant will persist across rebuilds)"
    codesign --force --sign "$SIGN_IDENTITY" "$STAGED/Contents/MacOS/$APP_NAME"
    codesign --force --sign "$SIGN_IDENTITY" "$STAGED"
else
    echo "  ad-hoc (run scripts/setup_dev_cert.sh once for a stable Accessibility grant)"
    codesign --force --sign - "$STAGED/Contents/MacOS/$APP_NAME"
    codesign --force --sign - "$STAGED"
fi

echo "==> Installing to $APP_PATH"
mkdir -p "$INSTALL_DIR"
# Quit any running instance so the binary swap succeeds and the user gets
# the freshly-built code on next launch.
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP_PATH"
mv "$STAGED" "$APP_PATH"

# Force LaunchServices to re-register so Spotlight and Finder pick up the
# new bundle (icon, Info.plist) without waiting for periodic indexing.
touch "$APP_PATH"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP_PATH" >/dev/null 2>&1 || true

if [[ "$RESET_PERMISSIONS" -eq 1 ]]; then
    echo "==> Resetting Accessibility grant for $BUNDLE_ID"
    if tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null; then
        echo "  ok — macOS will prompt on next launch."
    else
        echo "  warning: tccutil reset failed (no prior grant, or TCC blocked)." >&2
    fi
fi

echo
echo "Done."
echo "  $APP_PATH"
if [[ "$RESET_PERMISSIONS" -eq 1 ]]; then
    echo
    echo "Accessibility grant reset. Launch Ghost and approve the prompt in"
    echo "System Settings, Privacy & Security, Accessibility, then quit"
    echo "& relaunch Ghost."
elif [[ "$MATCH_COUNT" -eq 1 ]]; then
    echo
    echo "Signed with stable cert. Accessibility grant should persist across rebuilds."
    echo "If this is the first install, grant it once in System Settings,"
    echo "Privacy & Security, Accessibility, then quit & relaunch Ghost."
else
    echo
    echo "Run scripts/setup_dev_cert.sh once for a persistent Accessibility grant."
fi

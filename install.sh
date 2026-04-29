#!/bin/bash
#
# Ghost: paste-and-play installer.
# Builds from source, installs to ~/Applications, sets up a stable code-
# signing cert so the macOS Accessibility grant survives rebuilds, and
# launches the app. Idempotent: safe to re-run any time to update or
# repair the installation.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/TeXtUtility/Ghost/main/install.sh | bash
#
# Optional env vars:
#   INSTALL_DIR   where to clone the repo (default: ~/Ghost)
#   ICON_SRC      source PNG for the app icon (default: $INSTALL_DIR/logo.png)
#                 not required, the repo ships its own logo.png

set -euo pipefail

REPO_URL="https://github.com/TeXtUtility/Ghost.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Ghost}"
APP_NAME="Ghost"
APP_DST="$HOME/Applications/${APP_NAME}.app"

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
say()   { color "1;36" ">> $*"; }
warn()  { color "1;33" "!! $*"; }

# 1. Toolchain
if ! xcode-select -p >/dev/null 2>&1; then
    say "Installing Xcode Command Line Tools..."
    xcode-select --install >/dev/null 2>&1 || true
    warn "A system dialog should have appeared to install Command Line Tools."
    warn "Once it finishes, re-run this installer."
    exit 0
fi
if ! command -v swift >/dev/null 2>&1; then
    warn "Swift toolchain not found in PATH."
    warn "Install Xcode (App Store) or run: xcode-select --install"
    exit 1
fi

# 2. Repo: clone or fast-forward
if [ -d "$INSTALL_DIR/.git" ]; then
    say "Updating $INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch --quiet origin
    git -C "$INSTALL_DIR" reset --hard origin/main --quiet
else
    say "Cloning $REPO_URL into $INSTALL_DIR"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Stable code-signing cert (idempotent: no-op if already present)
say "Setting up code-signing cert"
"$INSTALL_DIR/scripts/setup_dev_cert.sh" | sed 's/^/    /'

# 4. Build + assemble app bundle + install to ~/Applications
mkdir -p "$HOME/Applications"
say "Building and installing $APP_NAME.app (about 30 seconds on first run)"
"$INSTALL_DIR/scripts/build_app.sh" | sed 's/^/    /'

# 5. Re-register with LaunchServices so Spotlight / Finder pick up the new
# bundle (icon, Info.plist) without waiting for periodic indexing.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP_DST" >/dev/null 2>&1 || true

# 6. Launch
say "Launching $APP_NAME"
open "$APP_DST"

cat <<EOF

  ${APP_NAME} is installed at:
    $APP_DST

  First-time setup:
    System Settings, Privacy & Security, Accessibility, toggle ${APP_NAME} on.
    The popover surfaces an in-app prompt with the right buttons if you
    miss this step.

  To update or repair:
    Re-run this installer (same one-liner).

EOF

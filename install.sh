#!/bin/bash
# MacTVMate installer
#   curl -fsSL https://raw.githubusercontent.com/eddie-jimenez/MacTVMate/main/install.sh | bash
#
# 1. Checks macOS 14+
# 2. Makes sure Homebrew and mpv (libmpv + FFmpeg) are installed — asks before installing anything
# 3. Apple silicon: downloads the latest release; Intel or no release: builds from source
# 4. Installs to /Applications (or ~/Applications) and opens it
set -euo pipefail

REPO="eddie-jimenez/MacTVMate"
APP_NAME="MacTVMate.app"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  \033[34m›\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
# Read answers from the terminal even when the script itself arrives through a pipe.
ask() {
  local reply=""
  if [[ -r /dev/tty ]]; then read -r -p "  ? $1 [Y/n] " reply < /dev/tty || true; fi
  [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

bold "MacTVMate installer"

# 1. macOS version
[[ "$(uname -s)" == "Darwin" ]] || die "MacTVMate runs on macOS only."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 14 )) || die "macOS 14 (Sonoma) or later is required — this Mac has $(sw_vers -productVersion)."
ARCH="$(uname -m)"
ok "macOS $(sw_vers -productVersion) on $ARCH"

# 2. Homebrew + mpv
if ! command -v brew >/dev/null 2>&1; then
  for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x "$p" ]] && eval "$("$p" shellenv)" && break; done
fi
if ! command -v brew >/dev/null 2>&1; then
  info "MacTVMate needs Homebrew to install its video engine (mpv)."
  if ask "Install Homebrew now? (from brew.sh — it may ask for your Mac password)"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [[ -x "$p" ]] && eval "$("$p" shellenv)" && break; done
  fi
  command -v brew >/dev/null 2>&1 || die "Homebrew is required. Install it from https://brew.sh and run this again."
fi
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

BREW="$(brew --prefix)"
if [[ ! -e "$BREW/opt/mpv/lib/libmpv.dylib" ]]; then
  if ask "Install mpv (video engine, via Homebrew — takes a few minutes the first time)?"; then
    brew install mpv
  else
    die "mpv is required."
  fi
fi
ok "mpv $(brew list --versions mpv | awk '{print $2}')"

# 3. Get the app
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
APP_SRC=""

# Release builds link Homebrew's libmpv at /opt/homebrew, so they fit Apple silicon with standard Homebrew.
if [[ "$ARCH" == "arm64" && "$BREW" == "/opt/homebrew" ]]; then
  info "Looking for the latest release…"
  URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep -o '"browser_download_url": *"[^"]*arm64\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')" || true
  if [[ -n "${URL:-}" ]]; then
    info "Downloading $(basename "$URL")…"
    curl -fL --progress-bar "$URL" -o "$TMP/app.zip"
    ditto -x -k "$TMP/app.zip" "$TMP/unzipped"
    APP_SRC="$TMP/unzipped/$APP_NAME"
    [[ -d "$APP_SRC" ]] || APP_SRC=""
  fi
fi

if [[ -z "$APP_SRC" ]]; then
  info "Building from source…"
  if ! xcrun --find swift >/dev/null 2>&1; then
    info "The Xcode Command Line Tools are needed to build."
    xcode-select --install 2>/dev/null || true
    die "Finish installing the Command Line Tools (a window should have opened), then run this again."
  fi
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP"
  (cd "$TMP/MacTVMate-main" && ./build-app.sh)
  APP_SRC="$TMP/MacTVMate-main/build/$APP_NAME"
fi

# 4. Install
DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"
if pgrep -x MacTVMate >/dev/null 2>&1; then
  info "Closing the running MacTVMate…"
  osascript -e 'tell application id "io.github.eddie-jimenez.MacTVMate" to quit' >/dev/null 2>&1 || pkill -x MacTVMate || true
  sleep 2
fi
rm -rf "$DEST/$APP_NAME"
ditto "$APP_SRC" "$DEST/$APP_NAME"
# Downloaded with curl, so normally not quarantined — clear it anyway so Gatekeeper doesn't block the ad-hoc signed app.
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true
ok "Installed $DEST/$APP_NAME"

open "$DEST/$APP_NAME"
bold "Done! Add your playlist in MacTVMate ▸ Settings ▸ Playlists."
echo "  To update later, run the same command again."
echo "  To uninstall: rm -rf \"$DEST/$APP_NAME\" ~/Library/Application\\ Support/MacTVMate"

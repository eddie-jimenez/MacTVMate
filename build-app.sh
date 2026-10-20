#!/bin/zsh
# Builds MacTVMate.app into ./build.
#   ./build-app.sh            release build
#   ./build-app.sh debug      debug build
#   ./build-app.sh --zip      release build + build/MacTVMate-<version>-<arch>.zip (for GitHub Releases)
# Needs Xcode or the Command Line Tools (xcode-select --install) and `brew install mpv`.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release; ZIP=0
for a in "$@"; do
  case "$a" in
    debug|release) CONFIG="$a" ;;
    --zip) ZIP=1 ;;
    *) echo "Unknown option: $a"; exit 2 ;;
  esac
done

# Prefer full Xcode if present (newer SDK), otherwise the Command Line Tools.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
command -v swift >/dev/null || { echo "Swift not found. Install Xcode, or run: xcode-select --install"; exit 1; }

BREW="$(brew --prefix 2>/dev/null || true)"
[[ -n "$BREW" ]] || BREW=$([[ -d /opt/homebrew ]] && echo /opt/homebrew || echo /usr/local)
[[ -e "$BREW/opt/mpv/lib/libmpv.dylib" ]] || { echo "libmpv not found. Run: brew install mpv"; exit 1; }
export HOMEBREW_PREFIX="$BREW"
export PKG_CONFIG_PATH="$BREW/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
[[ -n "$VERSION" ]] || VERSION=1.0.0

# Keep this machine's paths out of the binary.
SWIFT_FLAGS=(-c "$CONFIG" -Xswiftc -file-prefix-map -Xswiftc "$PWD=.")
swift build "${SWIFT_FLAGS[@]}"
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/MacTVMate"
APP=build/MacTVMate.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacTVMate"
cp Resources/MacTVMate.icns "$APP/Contents/Resources/MacTVMate.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacTVMate</string>
  <key>CFBundleDisplayName</key><string>MacTVMate</string>
  <key>CFBundleIdentifier</key><string>io.github.eddie-jimenez.MacTVMate</string>
  <key>CFBundleExecutable</key><string>MacTVMate</string>
  <key>CFBundleIconFile</key><string>MacTVMate</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>MacTVMate serves a remote-control page to your iPhone or iPad on this Wi-Fi.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP ($VERSION, $CONFIG)"

if [[ $ZIP == 1 ]]; then
  OUT="build/MacTVMate-$VERSION-$(uname -m).zip"
  rm -f "$OUT"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT"
  echo "Packed $OUT ($(du -h "$OUT" | cut -f1))"
fi

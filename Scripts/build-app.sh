#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="SimMediaDrop"
BUILD_DIR="$ROOT/.build"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

echo "→ Building $APP_NAME (release)…"
swift build -c release --product "$APP_NAME"

BIN="$BUILD_DIR/release/$APP_NAME"
if [[ ! -x "$BIN" ]]; then
  echo "Build product not found at $BIN" >&2
  exit 1
fi

echo "→ Assembling app bundle…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"

ICON_SRC="$ROOT/Assets/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>SimMediaDrop</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>dev.local.SimMediaDrop</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Sim Media Drop</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper/local quarantine is less noisy when moving the app
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Built: $APP_DIR"
echo "  Open with: open \"$APP_DIR\""
echo "  Or copy to Applications: cp -R \"$APP_DIR\" /Applications/"

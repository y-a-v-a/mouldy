#!/usr/bin/env bash
# Builds build/Mould.app from the Swift package: release binary, Info.plist, icon, ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Mould.app"
VERSION="${VERSION:-1.0.0}"

swift build -c "$CONFIG" --arch arm64 --arch x86_64 2>/dev/null || swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path 2>/dev/null)/Mould"
[ -x "$BIN" ] || BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/Mould"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mould"

# Icon, rendered by the app's own shader.
ICONSET="build/Mould.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN" --icon build/icon-1024.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Mould.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mould</string>
  <key>CFBundleDisplayName</key><string>Mould</string>
  <key>CFBundleIdentifier</key><string>nl.vincentbruijn.mould</string>
  <key>CFBundleExecutable</key><string>Mould</string>
  <key>CFBundleIconFile</key><string>Mould</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>NSHumanReadableCopyright</key><string>Vincent Bruijn 2026. Ieuw.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Signing. SIGN_IDENTITY picks the certificate; by default we use the first "Developer ID Application"
# identity in the keychain (needed for notarization), and fall back to ad-hoc signing without one.
# Force ad-hoc with SIGN_IDENTITY=-
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - --timestamp=none "$APP"
  echo "Built $APP (ad-hoc signed: runs here, but Gatekeeper will block it on other Macs)"
else
  # Hardened runtime + secure timestamp: both required by the notary service.
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --entitlements scripts/Mould.entitlements "$APP"
  codesign --verify --strict --deep "$APP"
  echo "Built $APP (signed by $SIGN_IDENTITY)"
fi

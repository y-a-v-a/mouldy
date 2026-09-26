#!/usr/bin/env bash
# Notarizes and staples build/Mould.app, then packages build/Mould.zip for distribution.
#
# One-time setup: store your notary credentials in the keychain (use an app-specific password
# from https://account.apple.com):
#
#   xcrun notarytool store-credentials mould-notary \
#     --apple-id you@example.com --team-id HFFHH9CJYF
#
# Then: make notarize   (or NOTARY_PROFILE=other-profile make notarize)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Mould.app"
PROFILE="${NOTARY_PROFILE:-mould-notary}"
ZIP="build/Mould.zip"

[ -d "$APP" ] || { echo "No $APP; run 'make app' first." >&2; exit 1; }
if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
  echo "$APP is ad-hoc signed; notarization needs a Developer ID signature (see SIGN_IDENTITY in build-app.sh)." >&2
  exit 1
fi

# The notary service takes a zip; ditto keeps the bundle's metadata intact.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Submitting to Apple's notary service (usually a few minutes)..."
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# Staple the ticket so Gatekeeper can verify offline, then re-zip the stapled app.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

spctl --assess --type execute --verbose "$APP"
echo "Notarized and stapled: $APP"
echo "Ready to share: $ZIP"

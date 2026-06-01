#!/usr/bin/env bash
#
# Build a distributable PubFinder.app and zip it for the Homebrew cask.
#
# Right now the app is **ad-hoc signed** (no Apple Developer account yet), so
# Gatekeeper will flag it on first launch — see RELEASING.md for how users get
# around that, and the commented NOTARIZATION block at the bottom for when you
# have a Developer ID.
#
# Usage:  ./scripts/build_release.sh
# Output: dist/PubFinder-<version>.zip  + its SHA-256 (paste into the cask)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="PubFinder"
CONFIG="Release"
DERIVED="$PROJECT_DIR/build-release"
DIST="$PROJECT_DIR/dist"

# Pull the marketing version straight from the build settings so it always
# matches what ships in the bundle.
VERSION="$(xcodebuild -project PubFinder.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION =/{print $2; exit}')"
VERSION="${VERSION:-0.0.0}"

echo "==> Building $SCHEME $VERSION ($CONFIG)"
xcodebuild -project PubFinder.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" clean build | tail -5

APP="$DERIVED/Build/Products/$CONFIG/PubFinder.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found"; exit 1; }

echo "==> Ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP" || true

echo "==> Zipping"
mkdir -p "$DIST"
ZIP="$DIST/PubFinder-$VERSION.zip"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "==================================================================="
echo " Built: $ZIP"
echo " Version: $VERSION"
echo " SHA-256: $SHA"
echo "==================================================================="
echo
echo "Next:"
echo "  1. Create GitHub release v$VERSION and upload the zip."
echo "  2. In Casks/pubfinder.rb set version \"$VERSION\" and sha256 \"$SHA\"."
echo "  3. Push the cask to your tap (see RELEASING.md)."

# --- NOTARIZATION (enable once you have an Apple Developer ID) ---------------
# Replace the ad-hoc sign above with a Developer ID sign, then notarize:
#
#   DEV_ID="Developer ID Application: Your Name (TEAMID)"
#   codesign --force --options runtime --timestamp \
#     --sign "$DEV_ID" "$APP"
#   /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
#   xcrun notarytool submit "$ZIP" --keychain-profile "PubFinderNotary" --wait
#   xcrun stapler staple "$APP"
#   /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip with stapled ticket
#
# (Store creds once: xcrun notarytool store-credentials "PubFinderNotary"
#  --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>)

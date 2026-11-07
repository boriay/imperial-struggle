#!/bin/bash
# Signs Imperial Struggle with a Developer ID certificate, sends it for notarization,
# staples the ticket and packs the final zip. Run it on a Mac.
#
# Once, before the first run, save the notarization credentials to the Keychain:
#   xcrun notarytool store-credentials imperial-notary \
#       --apple-id "YOUR_APPLE_ID" --team-id "YOUR_TEAM_ID"
#   (you type the app-specific password when asked; it never goes into any file)
#
# Usage:
#   ./sign_and_notarize.sh ImperialStruggle-macOS.zip
set -euo pipefail

INPUT_ZIP="${1:?Pass the path to ImperialStruggle-macOS.zip}"
PROFILE="${NOTARY_PROFILE:-imperial-notary}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ENTITLEMENTS="$HERE/entitlements.plist"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [ -z "$IDENTITY" ]; then
	echo "No Developer ID Application certificate found in the Keychain." >&2
	exit 1
fi
echo "Certificate: $IDENTITY"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ditto -x -k "$INPUT_ZIP" "$WORK"
APP="$(find "$WORK" -maxdepth 2 -name '*.app' -type d | head -1)"
[ -n "$APP" ] || { echo "No .app in the archive" >&2; exit 1; }
xattr -cr "$APP"

# Nested libraries first, then the app itself.
find "$APP/Contents" \( -name '*.dylib' -o -name '*.framework' \) -print0 2>/dev/null |
	while IFS= read -r -d '' lib; do
		codesign --force --timestamp --options runtime --sign "$IDENTITY" "$lib"
	done
codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

UPLOAD="$WORK/upload.zip"
ditto -c -k --keepParent "$APP" "$UPLOAD"
echo "Sending for notarization (usually 2-15 minutes)..."
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

OUT="$(dirname "$INPUT_ZIP")/ImperialStruggle-macOS-signed.zip"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
echo "Done: $OUT"

#!/usr/bin/env bash
# Developer ID sign, notarise, staple, zip, and print the cask values.
#   SIP_SIGN_ID         e.g. "Developer ID Application: Jane Citizen (TEAMID)"
#   SIP_NOTARY_PROFILE  a keychain profile created with `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "$0")/.."

missing=()
[[ -z "${SIP_SIGN_ID:-}" ]] && missing+=("SIP_SIGN_ID (Developer ID Application identity)")
[[ -z "${SIP_NOTARY_PROFILE:-}" ]] && missing+=("SIP_NOTARY_PROFILE (notarytool keychain profile)")
if (( ${#missing[@]} )); then
    echo "error: missing environment variables:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/Sip.app"
ZIP="build/Sip-$VERSION.zip"

SKIP_ADHOC_SIGN=1 ./scripts/build.sh

codesign --force --options runtime --timestamp --sign "$SIP_SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$SIP_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

# Re-zip so the archive contains the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo
echo "version \"$VERSION\""
echo "sha256  \"$SHA\""
echo "zip:    $ZIP"

#!/usr/bin/env bash
# Build the release zip and write its version and sha256 into Casks/sip.rb.
#
# With a Developer ID, set both of these to sign with the hardened runtime and notarise:
#   SIP_SIGN_ID         e.g. "Developer ID Application: Jane Citizen (TEAMID)"
#   SIP_NOTARY_PROFILE  a keychain profile created with `xcrun notarytool store-credentials`
# Without them, the app is ad-hoc signed only. The cask clears the quarantine flag on install so
# Gatekeeper doesn't block it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${SIP_SIGN_ID:-}" || -n "${SIP_NOTARY_PROFILE:-}" ]]; then
    missing=()
    [[ -z "${SIP_SIGN_ID:-}" ]] && missing+=("SIP_SIGN_ID (Developer ID Application identity)")
    [[ -z "${SIP_NOTARY_PROFILE:-}" ]] && missing+=("SIP_NOTARY_PROFILE (notarytool keychain profile)")
    if (( ${#missing[@]} )); then
        echo "error: notarised releases need both variables; missing:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
    NOTARISE=1
else
    NOTARISE=0
    echo "note: SIP_SIGN_ID not set, so this release is ad-hoc signed and not notarised." >&2
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/Sip.app"
ZIP="build/Sip-$VERSION.zip"
CASK="Casks/sip.rb"

if (( NOTARISE )); then
    SKIP_ADHOC_SIGN=1 ./scripts/build.sh
    codesign --force --options runtime --timestamp --sign "$SIP_SIGN_ID" "$APP"
else
    ./scripts/build.sh
fi
codesign --verify --strict --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if (( NOTARISE )); then
    xcrun notarytool submit "$ZIP" --keychain-profile "$SIP_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    # Re-zip so the archive contains the stapled ticket.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
sed -i '' -E \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
    "$CASK"

echo
echo "version  $VERSION"
echo "sha256   $SHA"
echo "zip      $ZIP"
echo
echo "Next:"
echo "  1. Upload $ZIP to a GitHub release tagged v$VERSION."
echo "  2. Copy $CASK into your tap repo's Casks/ folder and push it."

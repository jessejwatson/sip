# Sip

A macOS menu bar app that helps you drink enough water during work hours. It only reminds you when you fall behind pace, and it tracks whether you hit your goal each workday. All data stays on your Mac.

> "Sip" and the bundle ID `com.jessejwatson.sip` are placeholders until the first release.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later. Full Xcode is required, because SwiftUI's macros aren't included in the Command Line Tools. The scripts use `/Applications/Xcode.app` automatically. If you run `swift` directly while `xcode-select` points at the Command Line Tools, prefix it with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Develop

```bash
swift test                              # unit tests (pacing, reminders, store)
./scripts/build.sh && open build/Sip.app
```

`build.sh` produces a universal, ad-hoc signed `build/Sip.app`. Sip runs from the menu bar only and has no Dock icon. To quit it, open the drop icon and choose **Quit**.

To review UI changes without clicking through the app, render the popover and onboarding window to PNGs in light and dark mode. This is available in debug builds only and uses throwaway data:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
SIP_SNAPSHOT_DIR=/tmp/sip-snapshots .build/debug/Sip
```

To see onboarding again, use **Settings → Reset all data**, or run:

```bash
defaults delete com.jessejwatson.sip; rm -rf ~/Library/Application\ Support/com.jessejwatson.sip
```

## How reminders work

The goal ramps linearly from 0 at your start time to the full goal 30 minutes before you finish. You get a reminder only when all of these are true:

- it's a work day, not marked as leave
- you're within work hours and not in the last 30 minutes
- you're at least 200 ml behind pace
- you haven't logged a drink in the last 20 minutes
- the minimum gap since the last reminder has passed, or a snooze has just ended
- the screen is unlocked and awake

After you unlock or wake the Mac, the first possible reminder comes about 10 minutes later. Missed reminders are never sent in a burst.

## Release

```bash
./scripts/release.sh
```

This builds `build/Sip-<version>.zip` and writes its version and `sha256` into `Casks/sip.rb`. Then:

1. Create a GitHub release tagged `v<version>` on `jessejwatson/sip` and attach the zip. The cask downloads it from there, so upload this exact file; a rebuilt zip has a different checksum.
2. Copy `Casks/sip.rb` into the `Casks/` folder of your tap repo (a repo named `homebrew-<something>`) and push it.

Users install it with the tap's full name, because Homebrew's own catalogue resolves `sip` to a different app:

```bash
brew install --cask jessejwatson/<tap>/sip
```

Releases are ad-hoc signed and not notarised for now. The cask clears the quarantine flag after installing so Gatekeeper doesn't block the app. Once there's a Developer ID, set these to sign with the hardened runtime and notarise, then remove the cask's `postflight` block:

```bash
export SIP_SIGN_ID="Developer ID Application: … (TEAMID)"
export SIP_NOTARY_PROFILE="sip-notary"   # from `xcrun notarytool store-credentials`
./scripts/release.sh
```

To bump the version, edit `VERSION`. To regenerate the placeholder icon, run `swift scripts/make-icon.swift`.

## Data

- Settings: `~/Library/Preferences/com.jessejwatson.sip.plist`
- History: `~/Library/Application Support/com.jessejwatson.sip/history.json`

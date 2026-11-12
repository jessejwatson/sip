# Sip — Build Plan (v1)

A macOS menu bar app that helps people drink enough water during work hours. It reminds them only when they fall behind pace and tracks whether they hit their goal each workday. It's distributed as a Homebrew cask.

> **Working name:** "Sip", bundle ID `com.jessejwatson.sip`. Both are placeholders; confirm before the first release.

---

## 1. Constraints

- **Language/UI:** Swift 6, SwiftUI, `MenuBarExtra` (`.window` style). Minimum macOS 14 (Sonoma).
- **Zero third-party dependencies.** Apple frameworks only: SwiftUI, Observation, UserNotifications, ServiceManagement, AppKit where needed.
- **Build with Swift Package Manager**, not an Xcode project. A script assembles the `.app` bundle, so everything is buildable from the CLI.
- **Menu bar only:** no Dock icon (`LSUIElement = true`).
- **Light and dark mode** follow the system. Use semantic colours and materials only, with no hard-coded colours.
- **All data stays local.** No network calls, no analytics, no telemetry.
- **Units:** millilitres and litres. Use Australian English spelling in the UI.
- Never leave the app or any process running when finished. Tell the user the command to run it instead.

---

## 2. Repo layout

```
Package.swift
Sources/Sip/
  SipApp.swift              // @main, MenuBarExtra + Settings scene
  Model/
    Settings.swift          // work days, hours, goal, vessels, reminder interval
    DrinkEntry.swift        // id, timestamp, amountML
    Store.swift             // @Observable; load/save, today's total, history
    Pacing.swift            // pure functions: expected-by-now, behind?, recommendation
  Services/
    ReminderEngine.swift    // 60s tick, decides whether to notify
    Notifications.swift     // UNUserNotificationCenter, categories + actions
    PresenceMonitor.swift   // screen lock / sleep / wake
    LoginItem.swift         // SMAppService.mainApp wrapper
  Views/
    MenuContent.swift       // popover
    WeekStrip.swift
    OnboardingView.swift
    SettingsView.swift
Resources/
  Info.plist
  AppIcon.icns              // placeholder is fine for v1
Tests/SipTests/
  PacingTests.swift
  StoreTests.swift
scripts/
  build.sh                  // release build → Sip.app (ad-hoc signed by default)
  release.sh                // Developer ID sign, notarise, staple, zip, print sha256
Casks/
  sip.rb                    // template only; real cask lives in the tap repo
README.md
```

---

## 3. Data model and storage

**Settings** (UserDefaults, one Codable blob):
- `workDays: Set<Weekday>` (default Mon–Fri)
- `startTime`, `endTime` (hour + minute; default 08:30–16:30)
- `goalML: Int`
- `vessels: [Vessel]`, where `Vessel` is `{ name, amountML }` (default: one "Bottle", sized during onboarding)
- `reminderIntervalMinutes: Int` (minimum gap between reminders; default 45)
- `hasOnboarded: Bool`

**History:** stored as JSON at `~/Library/Application Support/com.jessejwatson.sip/history.json`.
- `entries: [DrinkEntry]`
- `excludedDays: Set<String>` (`yyyy-MM-dd`, for days marked as leave or sick)
- `dailyGoals: [String: Int]`: a snapshot of the goal for each day an entry is logged, so changing the goal doesn't rewrite past results.

Write atomically. Day boundaries use `Calendar.current` in local time. Refresh on `NSCalendarDayChanged` and `NSSystemTimeZoneDidChange`.

---

## 4. Onboarding (first launch)

A single window with three short steps:

1. **Work days and hours.** Day toggles plus start and end time pickers.
2. **Your bottle or cup.** Enter its size in ml, with presets of 250, 500, 600, 750 and 1000.
3. **Goal.** Prefill with the recommendation (below), shown both in litres and as "≈ 2.5 bottles". Include one line of guidance, a stepper/slider, and a "Use recommended" button.

**Recommendation:**
`recommended = 2300 ml × (workHours / 16)`, rounded to the nearest 50 ml and clamped to 500–2000 ml.

The guidance line reads: *"Based on Australian guidelines of about 2.1–2.6 L of drinks a day. Tea and coffee count. Adjust to suit you, or follow your doctor's advice."*

The final step includes a "Launch at login" toggle (default on), then requests notification permission.

---

## 5. Pacing and reminders

All of this lives as pure functions in `Pacing.swift`, which must be fully unit-tested.

- **Expected by now:** a linear ramp from 0 at `start` to `goal` at `end − 30 min`. It is 0 before start and equals the goal after.
- **Behind** means `expected − actual ≥ 200 ml`.

`ReminderEngine` ticks every 60 s and sends a reminder only if **all** of these are true:
- today is a work day and not an excluded day
- the current time is within work hours, but not in the last 30 minutes
- the goal hasn't been met yet
- the user is behind pace
- no drink was logged in the last 20 minutes
- no reminder was sent within `reminderIntervalMinutes` (or a snooze is active)
- the screen is unlocked and awake (`PresenceMonitor` watches `com.apple.screenIsLocked` / `screenIsUnlocked` and `NSWorkspace` sleep/wake)

On unlock or wake, **don't catch up** on reminders that were missed. Set `lastReminder = now − interval + 10 min` so the first possible reminder comes about 10 minutes after the user returns.

Focus modes are respected automatically through the system notification APIs.

**Notification:**
- Title: "Time for a drink". Body: "You're at 0.6 of 1.2 L."
- Actions: "Log [first vessel]" logs directly without opening the app, plus "Snooze 30 min".
- Register the category at launch, and handle actions in a `UNUserNotificationCenterDelegate`.

---

## 6. Menu bar

**Icon** (SF Symbols, template image):
- `drop` below 34%
- `drop.halffull` from 34% to 99%
- `drop.fill` when the goal is met
- On non-work or excluded days, show `drop` dimmed

**Popover (`MenuContent`):**
- A progress bar with "0.9 / 1.2 L" and the percentage.
- One quick-add button per vessel, plus a "Custom…" option with a small amount field.
- "Undo last", shown only if there was an entry today.
- **WeekStrip:** the last 7 days, each a dot. Filled means the goal was met, partial means some was logged, outline means none, a dash means a non-work or excluded day. Hovering or tapping shows the total.
- A "Mark today as leave" toggle.
- Footer buttons: Settings…, Quit.

---

## 7. Settings window

Include:
- work days and hours
- goal, with a "Use recommended" button
- the vessel list (add, edit, remove; at least one is required)
- reminder interval
- launch at login
- **Export CSV**, which writes `date,time,amount_ml` through a save panel
- **Reset all data**, behind a confirmation dialog

---

## 8. Build and distribution

**`scripts/build.sh`:**
1. `swift build -c release --arch arm64 --arch x86_64`
2. Assemble `build/Sip.app` with `Contents/MacOS`, `Info.plist` and `Resources`.
3. Ad-hoc sign with `codesign -s -`.

**`scripts/release.sh`:**
1. Sign with a Developer ID, hardened runtime enabled. The identity comes from the `S[118;1:3uIP_SIGN_ID` environment variable.
2. Zip the app with `ditto`.
3. Notarise with `xcrun notarytool submit --keychain-profile "$SIP_NOTARY_PROFILE" --wait`.
4. Run `xcrun stapler staple`, then re-zip.
5. Print the version and sha256 for the cask.

If the environment variables are missing, exit with a clear message.

**`Info.plist`:**
- `LSUIElement` true
- `CFBundleIdentifier`, plus `CFBundleShortVersionString` and `CFBundleVersion` set from a `VERSION` file
- `LSMinimumSystemVersion` 14.0

**`Casks/sip.rb`:** a template with `version`, `sha256`, `url`, `name`, `desc`, `homepage`, `app "Sip.app"`, `depends_on macos: ">= :sonoma"`, and:

```ruby
zap trash: [
  "~/Library/Application Support/com.jessejwatson.sip",
  "~/Library/Preferences/com.jessejwatson.sip.plist",
]
```

There's no in-app updater; updates come through `brew upgrade`.

---

## 9. Tests

Use Swift Testing or XCTest, run with `swift test`. Cover:
- **Pacing:** before start, mid-day, the last-30-minute window, after end, and goal already met.
- **Reminder decisions:** each suppression rule on its own, the snooze, and the no-burst-after-unlock behaviour. Inject a clock so the tests don't depend on real time.
- **Recommendation:** rounding and clamping.
- **Store:** today's total, rollover across midnight, excluded days, goal snapshots, and CSV output.

---

## 10. Out of scope for v1

Leave these for later versions:
- App Intents / Shortcuts ("Log a drink")
- per-drink types (tea, coffee and so on); everything is "a drink" in v1
- history charts beyond the 7-day strip
- calendar or meeting awareness
- iCloud sync
- localisation

---

## 11. Acceptance checklist

- [ ] `swift test` passes
- [ ] `scripts/build.sh` produces a launchable `build/Sip.app` with no Dock icon
- [ ] First launch shows onboarding, and the recommended goal changes with the work hours entered
- [ ] Quick-add, custom amount and undo all update the icon and progress immediately
- [ ] Logging from the notification action works while the popover is closed
- [ ] No reminders arrive outside work hours, on leave days, when the goal is met, or when the user is on pace
- [ ] No burst of reminders after unlocking or waking
- [ ] The week strip is correct across midnight, and changing the goal doesn't alter past days
- [ ] Data persists across quit and relaunch, and CSV export opens cleanly in Numbers or Excel
- [ ] Looks correct in both light and dark mode
- [ ] Launch at login toggles correctly

---

## 12. Workflow

- Pull the latest `main`, branch to `feature/v1`, commit in logical steps, push, and open a PR on Forgejo. Keep updating the same branch and PR until it's merged.
- Don't run the app and leave it running. When finished, report the commands to test:

```bash
swift test
./scripts/build.sh && open build/Sip.app
```

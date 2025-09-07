# Timer (Menu Bar Productivity Timer)

Lightweight macOS menu bar Pomodoro‑style timer. No Dock icon. Supports work/break sessions, progress or time display, optional notifications, and a simple settings window.

## Features
- Menu bar only (activation policy `.accessory`)
- Configurable work & break durations
- Two display modes: remaining time or percentage progress
- Auto notification on session completion (and optional 1‑minute warning)
- Pause / resume, quick switch between work & break
- Preferences persistence via `UserDefaults`
- Minimal codebase (pure Swift / SwiftUI + AppKit bridge)

## Requirements
- macOS 13+ (should run on earlier if SwiftUI API set permits)
- Xcode 15+

## Build (Development)
1. Open `Timer.xcodeproj` in Xcode.
2. Select scheme `Timer`, build & run. The timer appears in the menu bar (no Dock icon).
3. Open Settings via the status menu (⌘,).

## Release Build & DMG (Unsigned)
You can distribute without a paid Apple Developer account (users must bypass Gatekeeper the first run):

```bash
# Clean & build Release
xcodebuild -scheme Timer -configuration Release build

# Locate the app (adjust path if DerivedData differs)
APP=~/Library/Developer/Xcode/DerivedData/*/Build/Products/Release/Timer.app

# (Optional) Ad‑hoc sign to reduce some warnings
codesign -s - --deep --force "$APP"

# Stage DMG contents
rm -rf dmg_stage && mkdir dmg_stage
cp -R "$APP" dmg_stage/
ln -s /Applications dmg_stage/Applications

# Create compressed DMG
hdiutil create -volname "Timer" -srcfolder dmg_stage -ov -format UDZO Timer-1.2.3.dmg
```

## User Install (Unsigned App)
1. Download `Timer-1.2.3.dmg` and open it.
2. Drag `Timer.app` to `Applications`.
3. First launch: Right‑click (or Control‑click) `Timer.app` > Open > Open (bypasses unidentified developer warning). Subsequent launches are normal.

## (Optional) Developer ID + Notarization (Paid Account)
1. Archive in Xcode (Product > Archive).
2. Export with Developer ID or manually sign:
	```bash
	codesign --deep --force --verify --timestamp --options runtime \
	  --sign "Developer ID Application: Your Name (TEAMID)" /path/to/Timer.app
	```
3. Notarize:
	```bash
	ditto -c -k --sequesterRsrc --keepParent /path/to/Timer.app Timer.zip
	xcrun notarytool submit Timer.zip --apple-id "you@apple.com" --team-id TEAMID --keychain-profile AC_PASSWORD --wait
	xcrun stapler staple /path/to/Timer.app
	```
4. Build DMG (same as above) and optionally sign DMG:
	```bash
	codesign -s "Developer ID Application: Your Name (TEAMID)" Timer-1.2.3.dmg
	```

## Preferences Stored
Key | Purpose
----|--------
`workMinutes` | Work session length (minutes)
`breakMinutes` | Break session length (minutes)
`displayMode` | `time` or `progress`
`notificationsEnabled` | Bool
`oneMinuteWarningEnabled` | Bool
`pausedState` | Bool

## Source Structure
File | Description
-----|------------
`TimerApp.swift` | SwiftUI `@main` entry
`AppDelegate.swift` | Status item, timer logic, notifications, persistence
`SettingsWindow.swift` | SwiftUI settings panel
`Timer.entitlements` | Sandbox entitlements (if / when enabled)

## Roadmap Ideas
- Optional long break cycle
- Custom notification sound selection
- Automatic start next session toggle
- Launch at login helper
- Sparkle updates integration

## License
MIT (add actual LICENSE file if distributing publicly).

## Support / Issues
Open a GitHub issue with steps to reproduce.

---
Version: 1.2.3 (Build 5)

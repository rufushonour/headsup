<p align="center">
  <img src="Resources/icon.png" width="128" height="128" alt="Heads Up icon">
</p>

<h1 align="center">Heads Up</h1>

A macOS menu-bar app that blocks your screen full-screen just before a meeting starts, so you can't miss it.

## What it does (v1 / MVP)

- Reads events from every calendar connected to macOS Calendar (Google, Outlook, iCloud — anything Calendar.app syncs) via EventKit.
- Detects a meeting join link on each event, checking the event URL, then location, then notes, preferring known providers (Zoom, Google Meet, Teams, Webex, and others — see `Sources/HeadsUp/MeetingLink.swift`).
- Shows a full-screen, borderless alert on every display — above other windows and full-screen apps — a configurable amount of time before each meeting (default: 1 minute before).
- Alert has Join, Snooze, and Dismiss; snooze duration is configurable per-alert (a quick default, or a menu of other lengths) as well as in Settings.
- Menu bar dropdown lists the rest of today's meetings, each with a Join icon if a link was detected, or its location (e.g. a room name) if not.
- A proper Settings window (Cmd+, or the tray menu) for the default alert lead time, snooze duration, and per-calendar include/exclude + lead-time override.
- A first-launch Welcome screen explaining what the app does before asking for Calendar access.
- "Send Test Alert" menu item previews the full-screen alert on demand.

## Install

1. Download the latest `HeadsUp-<version>.dmg` from [Releases](https://github.com/rufushonour/headsup/releases), open it, and drag Heads Up into Applications.
2. Open `HeadsUp.app`. macOS will block it with **"HeadsUp.app" Not Opened** — click **Done**.
3. Go to **System Settings → Privacy & Security**, scroll to the Security section, and click **Open Anyway** next to the line about HeadsUp being blocked. Confirm when prompted.
4. Approve the Calendar access prompt when it appears.

This extra step is because the app isn't signed with an Apple Developer ID (that's a £100/year program) or notarized by Apple, so Gatekeeper doesn't recognize it as coming from a known developer. It's a one-time thing per download — after you click Open Anyway once, it launches normally from then on.

## Requirements

- macOS 13+ to run. Built here with Xcode 14.1 / Swift 5.7 (that toolchain's SDK caps at macOS 13, so the granular macOS 14 EventKit permission API isn't used — the legacy `requestAccess(to:)` API is used instead and works fine on newer macOS too).
- Calendar access — macOS will prompt on first launch. Approve it in System Settings → Privacy & Security → Calendars if you miss the prompt.

## Build & run

```
./Scripts/build_app.sh          # debug build -> build/HeadsUp.app
./Scripts/build_app.sh release  # release build
open build/HeadsUp.app
```

The script compiles via Swift Package Manager, packages the binary into a proper `.app` bundle with `Info.plist` (needed for the Calendar permission prompt to attach to the app rather than to Terminal), and ad-hoc code-signs it.

To build the `.dmg` used for GitHub Releases:

```
./Scripts/build_dmg.sh          # release build -> build/HeadsUp-<version>.dmg
```

This runs `build_app.sh release` first, then stages the `.app` alongside an `Applications` symlink and packs it with `hdiutil` — the standard drag-to-Applications layout.

## Cutting a release

```
./Scripts/cut_release.sh 0.1.1
```

This bumps the version in `Resources/Info.plist`, commits and pushes it to `main`, then creates and pushes the matching `vX.Y.Z` tag. Pushing that tag triggers `.github/workflows/release.yml` on GitHub Actions, which builds the `.dmg`, signs a new `appcast.xml` entry (Sparkle/EdDSA), commits the updated appcast back to `main`, and publishes the GitHub Release with the `.dmg` attached. Watch it with `gh run watch` or on the [Actions tab](https://github.com/rufushonour/headsup/actions).

The signing key lives in the `SPARKLE_PRIVATE_KEY` GitHub Actions secret (and is backed up in 1Password) — it's never committed to the repo. `Scripts/release.sh` is what the workflow runs under the hood; it also works locally (reading the key from this Mac's Keychain instead) if you want to build and inspect a release without publishing it.

For iterating on Swift code directly:

```
swift build
swift run   # note: permission prompts attach to whatever process invokes EventKit,
            # so prefer the packaged .app for testing calendar access
```

## Project layout

- `Sources/HeadsUp/CalendarService.swift` — EventKit access, polling, alert scheduling/snooze, today's meetings list.
- `Sources/HeadsUp/MeetingLink.swift` — join-link detection.
- `Sources/HeadsUp/AlertPresenter.swift`, `AlertView.swift` — the full-screen alert (one borderless window per screen).
- `Sources/HeadsUp/MenuBarController.swift` — status bar item, today's meetings, quick actions.
- `Sources/HeadsUp/SettingsView.swift`, `SettingsWindowController.swift` — the Settings window.
- `Sources/HeadsUp/WelcomeView.swift`, `WelcomeWindowController.swift` — first-launch onboarding.
- `Sources/HeadsUp/AppIconBadge.swift` — SwiftUI rendition of the app icon, reused across screens.
- `Sources/HeadsUp/AppDelegate.swift`, `main.swift` — wiring and entry point.
- `Resources/Info.plist` — bundle metadata and calendar usage descriptions.
- `Scripts/build_app.sh` — SPM build → `.app` packaging → ad-hoc codesign.
- `Scripts/build_dmg.sh` — `build_app.sh release` → `.dmg` packaging for GitHub Releases.
- `Scripts/release.sh` — builds the `.dmg` and generates a signed `appcast.xml` entry; used locally and by CI.
- `Scripts/cut_release.sh` — bumps `Info.plist`'s version and pushes the matching tag to trigger a release.
- `.github/workflows/release.yml` — on tag push, runs `release.sh`, commits `appcast.xml`, and publishes the GitHub Release.

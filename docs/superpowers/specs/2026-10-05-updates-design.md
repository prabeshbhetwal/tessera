# Check for updates — design

Date: 5 October 2026
Status: design approved in conversation; awaiting written-spec review

## Goal

Tessera can update itself the way most Mac apps outside the App Store do: a "Check for Updates…" command, automatic checks on a schedule the person chooses, release notes, and a verified one-click install. Releases are published from the developer's Mac with one script.

Success:
- A person on an older build chooses Check for Updates…, sees what changed, installs, and Tessera relaunches on the new build with Accessibility still granted.
- Automatic checks happen at the chosen frequency without being asked.

## Decisions (from review)

| Topic | Decision |
|---|---|
| Mechanism | Sparkle 2: checks a feed, shows release notes, downloads, verifies the EdDSA signature, installs, relaunches |
| Hosting | The main repository `prabeshbhetwal/tessera` becomes **public**. Releases are GitHub Releases; the feed `appcast.xml` lives at the repo root on `main` |
| Signing | Self-signed with the existing "Tessera Local Signing" identity. First install on another Mac needs right-click → Open; Sparkle updates after that install normally. Apple notarisation can be added later without redesign |
| Where settings live | Tessera's settings file (one source of truth: export, import and Reset include them); pushed to Sparkle on change |
| Placement | About pane button, menu bar item, General → Updates section |
| Default frequency | Weekly |

## Behaviour

### Settings (General → Updates)

| Setting | Options | Default |
|---|---|---|
| Check for updates automatically | on / off | on |
| Frequency | Daily, Weekly, Fortnightly, Monthly | Weekly |
| Download and install automatically | on / off | off |
| Include beta versions | on / off | off |

Below them: "Last checked: <relative date>" ("Never" before the first check). The frequency picker is disabled while automatic checks are off.

Frequencies map to Sparkle's check interval: Daily 86 400 s, Weekly 604 800 s, Fortnightly 1 209 600 s, Monthly 2 592 000 s (30 days).

### Commands

- **Check for Updates…**:
  - in the About pane, under the version line;
  - in the menu bar menu, above Quit.
- Both run Sparkle's user-initiated check, which always shows a result: "You're up to date", the update prompt with release notes, or an error.
- The command is disabled while a check is already running.

### Update prompt

Sparkle's standard window, showing:
- the new version;
- the release notes, written in the release script's notes file;
- the buttons Install Update / Remind Me Later / Skip This Version.

With "Download and install automatically" on, Sparkle downloads in the background and installs when Tessera next quits.

### Beta channel

Beta releases carry `<sparkle:channel>beta</sparkle:channel>` in the feed. Tessera's Sparkle delegate returns `["beta"]` from `allowedChannels(for:)` only when "Include beta versions" is on; stable items are always eligible.

### Versioning

- `CFBundleShortVersionString` is the human version, e.g. `0.2.0`, or `0.2.0-beta.1` for betas.
- `CFBundleVersion` is the build number Sparkle compares. It stays the existing increasing timestamp `YYYYMMDD.HHMMSS`, so every release is newer than the last.

## Components

### Core (`Packages/TesseraCore`, unit-tested)

| Unit | Responsibility |
|---|---|
| `UpdateInterval` | `daily, weekly, fortnightly, monthly`; `seconds: TimeInterval`; `displayName` |
| `UpdateSettings` | `checkAutomatically = true`, `interval: UpdateInterval = .weekly`, `installAutomatically = false`, `includeBetas = false`. Lives in its own file. |
| `TesseraSettings.updates` | One new property, `UpdateSettings()`. `SettingsMigration` fills it for older files; no schema bump. |

### App (`Tessera/`)

| Unit | Responsibility |
|---|---|
| Sparkle dependency | Sparkle 2 via Swift Package Manager in `project.yml`, the app's first external dependency |
| `UpdateService` (new) | `@MainActor`. Owns `SPUStandardUpdaterController`. `apply(_ settings: UpdateSettings)` sets `automaticallyChecksForUpdates`, `updateCheckInterval` and `automaticallyDownloadsUpdates`. `checkForUpdates()`. `canCheckForUpdates` and `lastUpdateCheckDate` are exposed for the UI. It is the updater delegate (`allowedChannels`). |
| Wiring | `AppDelegate` creates `UpdateService` at launch and applies the settings; `Coordinator.settingsChanged` re-applies them. (Coordinator is already oversized: one line at most.) |
| UI | About pane button; menu bar item; General → Updates section |
| `Info.plist` | `SUFeedURL` = `https://raw.githubusercontent.com/prabeshbhetwal/tessera/main/appcast.xml`; `SUPublicEDKey` = the public half of the release key; `SUEnableAutomaticChecks` = true |

### Release pipeline (`scripts/release.sh`, run on the developer's Mac)

`scripts/release.sh <version> --notes <file.md> [--beta]`:
1. Refuse to run with a dirty tree, or if `<version>` isn't newer than the latest release.
2. Build a Release configuration, signed with the local identity (same signing rules as `build-app.sh`), with `CFBundleShortVersionString` = `<version>`.
3. Zip the app with `ditto -c -k --keepParent`.
4. Sign the zip with Sparkle's `sign_update`. The EdDSA private key is created once with Sparkle's `generate_keys` and stays in the login Keychain; it is never committed.
5. Add an item to `appcast.xml`: version, build, length, signature, release-notes HTML, `sparkle:channel` for betas, and the GitHub Release download URL.
6. `gh release create v<version>` with the zip (`--prerelease` for betas), commit `appcast.xml`, push `main`. The script prints each step and stops on the first failure.

### Going public (one-off, before the first release)

1. Run a full-history secret scan (gitleaks or an equivalent) and fix anything it finds. Rewriting history is only done with explicit approval.
2. The developer changes the repository's visibility to Public in GitHub Settings. Tessera's tooling never does this.

## Edge cases

- **Offline or feed unreachable.** A user-initiated check shows Sparkle's error; automatic checks fail silently and try again next interval.
- **Accessibility and Screen Recording permissions.** Updates signed with the same identity keep the designated requirement, so the grants survive.
- **App in a folder Tessera can't write to.** Sparkle asks for authorisation, its standard behaviour.
- **Beta switched off while a beta is installed.** It stays installed; the next stable release newer than it is offered.
- **Settings import with no `updates` key.** Migration fills the defaults.
- **Development builds** (`build-app.sh`, Debug). They point at the same feed. Their build number is newer than any release, so they're never offered a downgrade.

## Testing

- **Core:**
  - `UpdateInterval.seconds` for all four frequencies;
  - `UpdateSettings` defaults;
  - an old settings file without `updates` migrates and validates;
  - the settings round-trip.
- **App:** builds with no new warnings, and the controls appear in all three places.
- **End to end (manual):**
  1. Publish `0.2.0-beta.1` as a beta.
  2. On a build with a lower build number and beta off, Check for Updates… says up to date.
  3. Turn beta on; the beta is offered with its notes.
  4. Install it; Tessera relaunches on the beta with Accessibility still granted.
  5. "Last checked" updates.

## Out of scope

- Apple Developer ID and notarisation (later; adds a notarisation step to `release.sh`).
- Delta updates.
- A CLI or AppleScript "check for updates" command.
- A Homebrew cask.

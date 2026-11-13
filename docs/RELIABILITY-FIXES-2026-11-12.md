# Tessera reliability fixes — 12 November 2026

Source changes address the 38-entry audit. [Per-finding implementation and verification checklist](reliability-fixes-2026-11-12.csv).

## Why saved splits could appear to stop working

The user's Dia + ChatGPT (`company.thebrowser.dia`, `com.openai.codex`) split remains in the settings file. Both split learning and automatic joining were enabled; no apps were excluded. Its recorded shares were approximately 59.5% / 40.5% on the C49 display.

The screenshot establishes an unarranged foreground group, but does not establish which event failed. Original implementation had several concrete failure paths:

- Window joining depended on app launch/activation; Cmd-N and background window creation were not observed.
- A group could stop being watched once windows overlapped or only one survived. Reopening a still-running app then missed its restoration context.
- Restoration context was keyed only by app, losing one display when the same app closed on multiple displays.
- Core Graphics includes covered windows in its on-screen list. These could change the app multiset used for exact split lookup. At diagnosis time, System Settings also had exposed content; that is a different group from the two-app screenshot.
- Accepted individual AX writes were treated as successful placement even when actual window size/position differed.

## Implemented behaviour

Window creation now has an app-level Accessibility observer. Existing groups are retained during a join even when a newly created window covers them. Explicit tiling excludes fully covered windows, while leaving partially exposed windows eligible. Closed-window recovery is kept per app and display and works for reopen as well as process launch. Startup restoration only recovers overlapping known groups; it preserves non-overlapping manual arrangements. Space changes clear obsolete watches and window identity is checked, rather than only matching app names.

Placement retries bounded writes and reads actual frames back. Constrained bottom placements retain their bottom edge. Partial tiling reports constrained/refused placements. Undo handles active movement, partially completed batches, later standalone commands and transient write failures. Cancellation retains a recovery entry. Frames from disconnected displays are brought back within connected screen bounds.

Settings saves run promptly and termination waits for a final save. Save failures are visible with Retry. Imports validate input safety, save before acknowledging success and retain a uniquely named backup of previous settings, including first import into a new profile. Cycle references, numeric controls, display selection, recorder ownership, query-scoped search, accessibility announcements, destructive-action confirmations and preview feedback were corrected. Release signing verifies the pinned certificate identity.

Physical motion clipped by the display boundary is retained for Ring selection without warping the pointer or changing gesture thresholds. Drawing and selection retain the same origin; the selected-action caption remains constrained to the display. Palette glyphs near a physical edge can still extend beyond that edge. Physical mouse/trackpad calibration requires live verification.

## Verification

| Check | Result |
|---|---|
| Core suite | 471 tests / 41 suites passed; 20 new regression cases |
| Native actor/input/lifecycle checks | 27 passed, exercising production code with isolated frame/presence/enumeration I/O and synthetic input; desktop windows were not moved |
| Startup/socket cases | 8 passed, including delayed executor startup and 64 KiB framing/timeout boundaries |
| Production Ring rendering | 131 checks passed; image fixture produced |
| Native app build | Full build passed from an isolated source copy |
| Signature/package smoke | Local build signed with the existing certificate; pinned identity, strict signature, resources and CLI usage verified |
| Review | Two independent source reviewers; their actionable findings corrected, with extra Undo/import regressions |
| Diff/shell checks | Whitespace and shell syntax checks passed |

Regression evidence includes failing tests against the original code for column caps, mouse-up pairing, unsafe imports, duplicate cycle names and shortcut conflicts. Later review exposed a partially completed batch Undo and newer-command ordering gap; native regressions failed before their corrections.

CI now includes native reliability checks. New Swift source files remain under 300 lines. Build products remain outside the repository. Existing untracked `.mcp 2.json`, `AGENTS 2.md` and `CLAUDE 2.md` were preserved. No commit, push or public release was made.

## Installation and live verification

Local `0.2.0-beta.25-dev`, build `20261112.143400`, is installed at `/Applications/Tessera.app`. Original app remains at `/Applications/_trash/tessera-beta24-before-reliability-20261112/Tessera.app`; its actual bundle version was beta.25 despite the earlier folder label. All intermediate installed test builds are retained.

Live verification exposed a 300 ms observer gap after Undo and a later intermittent missed minimisation. The revision keeps lifecycle subscriptions active, seeds/updates baselines without dropping subscriptions, uses timestamped verified placement geometry, and reconciles disappearance against actual AX state. Existing-window announcements are filtered by identity so unhiding does not join an old window again. That earlier reconciliation build passed 40 measured live checks for Dia and the original ChatGPT window. Saved split and original windows were preserved. See [live installation record](INSTALL-VERIFICATION-2026-11-13.md).

Subsequent Claude quit investigation found membership loss before late termination, stale asynchronous/callback work and missing immediate-reopen context. Additional corrections passed 27 native and 62 live workflow checks, including exact tiled-triple Cmd-Q and rapid relaunch. See [latest quit-recovery record](QUIT-RECOVERY-2026-11-13.md).

Not covered live: monitor unplugging, multiple Spaces, physical edge-gesture calibration, VoiceOver and the earlier Ring-slider accessibility-tree anomaly. These remain distinct from the verified current-display pair workflow.

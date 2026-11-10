# Tessera 1.0 checklist

1.0 is a promise: Tessera installs on anyone's Mac by following the README (one documented first-open step), does what the User Guide says, and never breaks a person's settings or layouts on update. Until every **Must** box is ticked, releases stay `0.x`.

Status as of 0.2.0-beta.22 (11 Nov 2026).

## Path

1. Finish the 0.2.0 betas and ship plain `0.2.0`.
2. New feature batches become `0.3.0`, `0.4.0` and so on; fixes to a shipped minor become `0.2.1`, `0.2.2`.
3. Feature freeze: `1.0.0-beta.N`, then `1.0.0-rc.N` (release candidates, fixes only).
4. `1.0.0` once an RC has gone a week of daily use with no Must-fix bug.

## Must (blocks 1.0)

### Install and update on any Mac
Releases are signed with the self-made "Tessera Local Signing" certificate, not Apple's paid Developer ID (no budget for the Apple Developer Program yet). On another Mac, macOS blocks the first open with "Apple could not verify…". 1.0 ships this way, with the first open documented; Developer ID waits for budget (see Later).
- [ ] **First-open steps in the README and User Guide**, with a screenshot: open Tessera once, get the warning, then System Settings › Privacy & Security › **Open Anyway**. One time only; Sparkle updates after that open without it.
- [ ] **Same certificate for every release.** The signature stays the same, so macOS keeps the Accessibility grant across updates. Back up the "Tessera Local Signing" certificate and its private key (export from Keychain Access to an encrypted `.p12`, stored off this Mac): losing it means every user re-grants Accessibility.
- [ ] **Clean-Mac install test.** On a Mac (or a new macOS user account) that has never run Tessera: download from the release page, follow the README's first-open steps, finish onboarding, grant Accessibility, tile windows. No Terminal steps.
- [ ] **Update test from the oldest supported build.** An installed 0.x release takes the 1.0 update through Sparkle and keeps its settings, learned splits and Accessibility grant.

### Nothing known broken
- [ ] **Plain-Command-key ring trigger issue** (open since 5 Oct) fixed, or the option removed.
- [ ] **On-screen checks never done** for shipped features, walked through by hand:
  - [ ] Ring Directions picker glide and lift; Learned splits sheet Esc/Return and a real forget (beta.16)
  - [ ] Settings search focus after widening the sidebar (beta.17)
  - [ ] ⌥Return in search results from a real keyboard; Apple Intelligence "Best match" section (beta.20)
  - [ ] Columns submenu "No Window in Front" state (beta.21)
  - [ ] Update from inside the app to beta.22 (beta.22)
- [ ] **In-app help phase 1 hands-on pass** done.
- [ ] **A week of daily use on both displays** (MacBook and the C49) with no Must-fix bug.

### Settled behaviour
- [ ] **Feature freeze declared.** No new settings or moved panes after `1.0.0-beta.1`; anything new waits for 1.1.
- [ ] **Settings format frozen.** `schemaVersion` and `SettingsMigration` load every file written by 0.2.0 or later; a test loads a saved 0.2.0 file.
- [ ] **User Guide matches the app.** Every pane, menu item and shortcut in `docs/USER-GUIDE.md` exists, with the same names.

### Safety and trust
- [ ] **Accessibility and Reduce Motion pass:** every Settings control reachable by keyboard and VoiceOver, glides off under Reduce Motion (rules in `docs/PRODUCT.md`).
- [ ] **Automation socket and CLI reviewed:** `tessera.sock` only accepts the current user; no command moves windows of excluded apps.
- [ ] **Licence and notices current:** `THIRD-PARTY-NOTICES.md` lists every bundled component.

## Should (aim for 1.0, can slip to 1.1)
- [ ] A window shown without its app becoming active still joins the split and fills its gap on close.
- [ ] Splits editor (miniatures, percentages) from the learned-splits spec.
- [ ] CI runs an app-level `xcodebuild test`, not only the core package, automation and ring checks.
- [ ] 1.0 release notes written as a "what Tessera does" page, not a diff from the last beta.

## Later (when budget allows)
- [ ] **Developer ID signing and notarisation** (Apple Developer Program, paid yearly). Removes the first-open warning. Add `notarytool submit --wait` and `stapler staple` to `scripts/release.sh` after the build. The certificate change makes every user re-grant Accessibility once: do it in one release and say so in its notes.

## Not needed for 1.0
- Mac App Store. Sandboxing blocks the Accessibility window control Tessera depends on; GitHub + Sparkle stays the channel.
- Translations. en-AU only.
- In-app help phases 2–5.
- Older macOS. The floor stays macOS 15.

## Decisions for Sir
1. Which items, if any, move between Must and Should.
2. When to call the 0.2.0 betas done and ship plain `0.2.0`.

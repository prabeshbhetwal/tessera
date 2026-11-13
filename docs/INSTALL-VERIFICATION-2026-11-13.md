# Tessera installation and live verification

Latest installation: build `20261112.143400`. Subsequent Claude Cmd-Q investigation reproduced and corrected further membership/ordering defects. See [Claude quit recovery](QUIT-RECOVERY-2026-11-13.md) for 27 native and 62 live workflow checks. The sections below retain earlier build history.

The first local reliability build was installed at `/Applications/Tessera.app`. Previous app was preserved at `/Applications/_trash/tessera-beta24-before-reliability-20261112/Tessera.app`. Despite the backup folder's earlier label, its actual bundle version was beta.25, build `20261112.053640`; its executable hash was verified unchanged after backup.

The newer beta.25 mouse-only split-learning fix was incorporated before installing, together with its “Already in your split” feedback.

## Live evidence so far

- Saved Dia/ChatGPT split remains 59.4792% / 40.5208%, corresponding to AX frames `[0,30,2284,1050]` and `[2284,30,1556,1050]` on this display.
- Opening Dia restored that pair automatically. ChatGPT's original window ID951 remained open throughout.
- Five equal-tile → remembered-split cycles passed measured-frame checks.
- One Undo restored both tiled windows.
- Settled ChatGPT minimisation grew Dia to `[0,30,3840,1050]`; restoration returned both windows to their saved split.
- Rapid minimisation immediately after Undo failed in an isolated desktop run: Dia remained2284 points wide. Undo had dropped lifecycle subscriptions during a 300 ms re-arm, and vacancy geometry could also remain from the prior equal layout.
- Third-app window creation changed the active app group; these runs were treated as interference, not successful pair-only checks.

## Observer correction

The revised build preserves close/minimise subscriptions across Undo and same-group layout changes, subscribes new groups before moving them, seeds the baseline immediately and uses timestamped verified placement history to recover newer Undo geometry. Stale learning work is cancelled. Hidden/minimised windows are explicitly excluded.

The observer revision was installed under the user's explicit verification-session approval. Ten native checks, native build, pinned signing identity and package checks passed. All 19 measured live checks passed, including five equal-tile/remembered-split cycles, batch Undo, rapid Undo→minimise (181 ms), minimise/restore of both apps, Cmd-N in running Dia, closing the test window and restarting Tessera from overlapping windows. The saved pair remained unchanged throughout. ChatGPT window 951 and original Dia window 1389 remained open; only newly created blank test windows were closed. Other apps' prior visibility was restored and checked.

Dia reports its minimised window as an AXDialog, so the test controller was corrected to find it. A transient AX close return was judged by the actual window disappearance and final layout, rather than assuming failure from the return code. These were test-controller issues, not additional product failures.

## Final reconciliation revision

Repeat testing of the next observer-identity revision still missed a Dia minimisation. Earlier successful runs therefore did not establish durable recovery. The final revision checks WindowServer identities once per second while a group is watched and, only when a watched window disappears, confirms minimisation/destruction through AX. It also checks before abandoning a group during re-arm or learning. Hidden/live windows are not treated as removed. Recovery remains single-flight, respects movement/cancellation and the leave-space setting, and cannot process the same stopped watch twice.

Existing-window creation announcements are filtered by window ID, so unhiding an old window does not make it join as a new window. Genuine Cmd-N windows still join.

The final installed build passed 40 measured live checks: the complete 19-check workflow, 20 additional rapid Undo→minimise/restore checks across both apps, and a final foreground/frame check after restoring prior surviving apps' visibility. The rapid Undo→minimise interval in the complete run was 158 ms. Original ChatGPT window 951 and Dia window 1389 remain open at `[2284,30,1556,1050]` and `[0,30,2284,1050]` respectively. The saved pair, including its timestamp, matches the pre-install settings snapshot exactly.

Thirteen native checks passed, including leave-space and immediate/duplicate removal regressions. Build, pinned signature and package checks passed. Source review found no further actionable reconciliation regression. The final run did not log a fallback activation; the measured results establish successful workflows, rather than proving that macOS dropped an event during that run.

Installed local version: `0.2.0-beta.25-dev`, build `20261112.135709`. Original and all three intermediate installed builds remain backed up. Source changes are local; no public release was made.

Final evidence: `final-installation-verification-reconciliation.json`, `pair-live-results-reconciliation.json`, `pair-live-results-reconciliation-repeat.json`, `post-unhide-final-frame-check.json`, `native-checks-reconciliation.log` and `build-reconciliation.log`. Earlier failures and superseded verification files are retained.

Live scope: this C49 display and this Dia/ChatGPT pair. Monitor hotplug, multiple Spaces, physical edge gestures and VoiceOver remain unverified.

Evidence directory: `/Users/prabeshbhetwal/Documents/Codex/2026-11-12/tessera-install-live-test-xrnixwz4`.

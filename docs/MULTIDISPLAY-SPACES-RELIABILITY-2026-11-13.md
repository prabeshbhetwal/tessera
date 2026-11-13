# Multiple displays, hotplug and Spaces reliability

Installed development build: **20261113.012556**, version `0.2.0-beta.25-dev`. Source and build-copy Swift files match. Stable signing identity and installed package checks pass. No commit, push or public release was made.

This extends [quit recovery verification](QUIT-RECOVERY-2026-11-13.md). Physical display/cable testing was unavailable; the user requested virtual displays instead.

## Defects found and corrected

| Defect | Resulting behaviour |
|---|---|
| A close during a full-screen Space transition lost the original group, leaving the returning survivor in its old slot | Groups and pending recovery are retained per display and Space; returning revalidates membership before filling the vacancy |
| A notification on one display could cancel unrelated display recovery | Space changes invalidate only the affected display; topology changes invalidate all stale coordinate work |
| Queued work or an animated move could continue with an old primary height, display layout or Space | Producers capture a context before suspension; the actor checks context and cancellation at frame-write boundaries |
| Undo saved only global coordinates | Undo also records source display identity/bounds; it maps frames to the same display or a reachable remaining display |
| A standard-role, layer-zero full-screen window was eligible for tiling | Batch eligibility checks AX full-screen state; individual placement returns an exit-full-screen message |
| A refused fill could lose its original vacancy or claim recovery completed | Failed candidates remain separate from settled frames, with bounded polling and two delayed retries; persistent refusal waits for a later event |
| A settings change or stale recovery could commit over newer state | Per-display policy versions, record revisions and baseline checks reject stale commits |
| A manual placement could be undone by queued recovery | Explicit placement and hand adjustment supersede automatic work on the affected displays |
| A new window covered by the expanded survivor was omitted from joining | Join retains genuine newcomer IDs while excluding older covered windows |
| A second rapid creation event could cancel the first newcomer's attempt | Unprocessed newcomer IDs survive replacement looks and activation events |
| WindowServer presentation bounds change in Mission Control | CG supplies on-screen IDs and stacking order; AX supplies eligibility, exposure and placement geometry. Transformed CG bounds no longer prefilter normal window geometry |
| AppKit screen snapshots can lag the current CG topology | Bounded convergence checks delay recovery until display snapshots agree |

Runtime workspace retention expires inactive records after 48 hours and uses a soft total cap of `max(32, active workspace count)`. Active records remain protected. Missing Space identity uses conservative invalidation; optional read-only private Space APIs are not required for ordinary explicit tiling.

## Automated verification

| Check | Evidence |
|---|---|
| Core geometry/settings/input tests | **477 tests, 42 suites passed** |
| Native actor, lifecycle, workspace, policy and input checks | **53 passed** on the final source |
| CLI/socket verification | Passed framing, 64 KiB boundary, invalid requests, EOF and timeout recovery, bridge isolation |
| App build, signature and installed packaging | Passed |
| Source/build-copy comparison, whitespace and shell syntax | Passed |

Native regressions include invalidation before/during movement, primary-height changes, Undo mapping, independent Space changes, missing Space SPI, suspended-workspace quits, close immediately before switching Space, cancelled startup restoration, retained partial recovery, policy changes during a glide, unresolved absence on return, manual override, protected minimised gaps, rapid newcomer replacement, cache retention and delayed display convergence.

## Live verification

The WindowServer lab used C49 plus landscape, portrait and app-testing virtual displays. Portrait origin was negative; the primary-display test changed the primary height from 1080 to 1920. Actual modes were C49 at 2× and virtual displays at 1×. A virtual HiDPI request did not persist as a 2× mode; earlier progress descriptions calling that virtual display 2× are superseded by the recorded mode measurements.

| Scenario | Result and evidence boundary |
|---|---|
| Independent landscape and portrait tiling | Passed, including unequal memories and duplicate windows from one process |
| Same-process close and new-window join | Passed |
| Close during full-screen Space transition, then return | Failed on build 143400; passed on the first corrected workspace build 005841 |
| Full-screen eligibility | Standard-role fixture excluded from batch tiling; native refusal-before-write regression passes |
| Primary becomes the taller portrait display, then C49 again | Passed on revision 010852; landscape split/coordinates retained |
| Actual virtual disconnect during a glide | Production actor stopped stale motion; isolated Undo returned the owned window to a reachable remaining display |
| Reconnect with the same display descriptors | Saved unequal landscape split restored; session CG display number changed |
| TextEdit and Finder | Tiling, minimise-fill and split restoration passed |
| Rapid covered newcomers | Both acknowledged creations joined; 156 ms acknowledgement interval observed. Closing both restored the original duplicate-app memory. Replayed with the overview closed |
| Fixed-size AppKit fixture and Calculator | Resizing limitations produced an explicit partial placement message; no full-success claim or hang |
| Ordinary Desktop Space switch | Temporary Desktop created and activated on the app-testing virtual display; original real-app windows remained on their origin Desktop |
| Close while the origin Desktop is inactive | Owned fixture window closed through its retained in-process reference. Returning restored TextEdit/Finder's remembered pair; unrelated landscape pair remained unchanged on final build 012556 |
| Mission Control geometry | Production visibility observer returned normal AX frames, including while the overview displayed transformed thumbnails |

The hotplug glide/Undo check used the production actor compiled into an isolated native helper with its own Undo history, preventing interference with the user's global Undo stack. It exercised real WindowServer display removal, not injected topology alone. It is not evidence of a physical cable disconnect.

Mission Control controls on this OS were hosted by **WindowManager**, rather than Dock. The temporary Desktop migrated to C49 when its virtual display was removed; it was then removed with its verified `AXRemoveDesktop` action. Final Space inventory contains only original C49 Space 1.

Several controller failures were excluded from passing evidence: an unacknowledged fixture command, a close attempt against Finder's inactive AX window, overlapping CLI tile requests, and CG thumbnail bounds mistaken for normal geometry. Later runs used acknowledged creations, retained fixture references, serial commands and normal AX-frame checks. These failures were not counted as app regressions.

## Deliberation

Initial debugger/architecture review used Codex, Gemini and DeepSeek. Follow-up Codex reviews checked the workspace design, state commits, newcomer handling and presentation geometry. Grok remained disabled. One Gemini follow-up timed out and supplied no review result.

The reviews produced concrete corrections for stale commits, retained partial recovery, policy invalidation, bounded retries, convergence, rapid newcomer loss and transformed presentation bounds. Suggestions were checked against source and regressions; provider agreement was not treated as runtime proof.

## Final state and remaining limits

- Installed executable/build, matching source, package verification and check logs are recorded in `final-verification.json`.
- All three virtual displays, the temporary Desktop, owned fixture processes and test windows were removed.
- Test-only split records were removed. Settings semantically match the starting snapshot; the help moment array differs only in serialisation order.
- All C49 learned splits and timestamps are unchanged, including the Dia/ChatGPT pair.
- Original ChatGPT window **951**, Dia window **1389** and current Claude window **2331** remain open. Final AX frames: ChatGPT `[1796,30,1101,1050]`, Dia `[0,30,1796,1050]`, Claude `[2897,30,943,1050]`.
- Pre-session build 143400 is preserved at `/Applications/_trash/tessera-before-multidisplay-wstvx7gl/Tessera.app`. Intermediate builds and the original build 053640 remain backed up too.
- Physical cable hotplug, every third-party app, all display-driver/OS combinations, VoiceOver and long-duration soak behaviour remain unverified. An AX request already executing at invalidation can complete; later writes stop. App minimum sizes can still prevent an exact layout and are reported as partial.

Evidence directory: `/Users/prabeshbhetwal/Documents/Codex/2026-11-13/tessera-multidisplay-spaces-t45pg1th`. It contains before-fix failure records, live frame/Space snapshots, actual display modes, Deliberation responses, fixture/helper source, build/test logs, settings cleanup and final verification.

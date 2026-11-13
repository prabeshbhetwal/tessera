# Claude quit recovery — 13 November 2026

Installed: `0.2.0-beta.25-dev`, build `20261112.143400`, at `/Applications/Tessera.app`.

## Failure and correction

The earlier 40 live checks did not cover quitting a distinct third app. The supplied screenshot shows a vacancy after Claude quit; it does not establish which macOS event ordering occurred. Its capture predates the previous recovery build, but additional source testing found genuine remaining defects.

A deterministic native regression reproduced `membershipLostBeforeTermination`: after four uncertain window-list reads, re-arming replaced the managed Dia/ChatGPT/Claude group with its two survivors. Claude's later termination then had no recorded membership to recover. A second regression reproduced `earlyTerminationContextLost`: AX destruction stopped the child watch before Workspace termination arrived, leaving no immediate-reopen context until a later move succeeded.

The correction separates uncertain geometry from lifecycle ownership:

- Unknown disappearance retains the managed group after fast retries end. Confirmed close, minimise, process exit, hide, exclusion and movement to another display remain distinct. Space changes still invalidate old work.
- Watch revisions are captured before window-list reads and checked after AX reads. Old callbacks must refer to a currently watched element. Stale work cannot close or replace a newer group.
- Pending recovery retains its group until completion or cancellation. Workspace termination can recover reopen context from that snapshot even after AX destruction ended the child watch. Re-arming waits for active recovery.
- Each absent member must have confirmed removal before its space is consumed. Temporary empty/unavailable queries retry; unrelated exposed windows cause an explicit skip.
- Recovery retries window-list lag for roughly ten seconds with bounded backoff. Unknown/hung window checks back off to five seconds; authoritative AX/Workspace events remain immediate.
- Settings and display context are rechecked after asynchronous reads, before policy exits and writes. Disabled minimise/gap filling and newly excluded apps are respected. A no-move rejoin consumes its old restoration context.

Lifecycle logs record transaction IDs and recovered/skipped/cancelled/timed-out outcomes without window titles.

## Deliberation

Used the Deliberation debugger, architect and code-reviewer roles through seven iterations. Successful advisory responses came from configured Codex and Gemini providers. DeepSeek timed out and is not counted as a completed review. Initial client timeouts and Gemini's headless command restriction were handled with longer call deadlines and inline-only source review; permissions were not weakened.

| Suggestion | Decision and evidence |
|---|---|
| Retain membership across uncertain absence | Accepted; regression failed before correction |
| Guard both list and AX reads against newer watches | Accepted; controlled suspended-read regressions |
| Distinguish confirmed quit from another unavailable member | Accepted; mixed-absence regression |
| Revalidate settings before moves and early policy exits | Accepted; gated disable/enable tests |
| Keep pending group for AX-destroy → Workspace-terminate ordering | Accepted; second failing regression, then passing test |
| Sort MRU windows to fix split lookup | Rejected: SplitKey sorts its multiset and SplitApplier pairs by app/reading order; inverted-MRU native recovery passes |
| Eagerly purge absent refs from restoration cache | Unnecessary: join verifies current survivors and permits restored subsets. Final advisory follow-up accepted this consumer behaviour |

Advisory opinions were checked against source and tests; agreement alone was not treated as verification.

## Verification of installed build

| Check | Result |
|---|---|
| Native actor/input/lifecycle checks | 27 passed; isolated frame, presence and enumeration boundaries; no desktop window writes |
| Confirmed Claude quit/reopen timing cycles | 12 passed; includes quits before joining and after joining, with different foreground apps |
| Exact measured tiled triple → pair | 8 passed, including two acknowledged Cmd-Q inputs |
| Immediate relaunch during pending recovery | 2 passed |
| Original pair workflow | 19 passed: tile/remembered restore, batch Undo, minimise/restore, Cmd-N, close and restart from overlaps |
| Rapid Undo → minimise/restore repeats | 20 passed |
| Final original-window foreground/frame check | Passed |
| Native build, pinned signature and installed package smoke | Passed |
| Whitespace and shell syntax checks | Passed |

Total: 62 live workflow checks. Earlier synthetic input/menu quits that did not terminate Claude were rejected as controller failures and excluded from passing counts. Core code was unchanged by this correction; the earlier 471 tests/41 suites remain prior evidence, rather than a new core-suite run.

Original ChatGPT window **951** and Dia window **1389** remain open and foremost. Final AX frames are ChatGPT `[2284,30,1556,1050]` and Dia `[0,30,2284,1050]`. The saved 59.4792%/40.5208% pair, including its timestamp, matches the pre-install snapshot.

The preceding build is preserved at `/Applications/_trash/tessera-quit-ownership-backup-20261113-bUwJSkeD/Tessera.app`; its executable hash matches the preceding installation record. Original app and earlier backups remain intact. No commit, push or public release was made.

Evidence: `/Users/prabeshbhetwal/Documents/Codex/2026-11-13/tessera-quit-recovery-s7txrjw_`. `installation-and-verification.json` records build/hash, frames, settings and counts; separate directories retain both live matrices and Deliberation responses. Before-fix failures and runtime lifecycle logs are retained.

Live scope remains this C49 display and these original Dia/ChatGPT windows. Multiple displays, hotplug, Spaces, VoiceOver and physical edge-gesture calibration remain unverified. Finite tests establish the exercised workflows; they do not guarantee every future OS/app event ordering.

Subsequent virtual multi-display, hotplug, Desktop/full-screen Space and broader app verification: [Multiple displays and Spaces reliability](MULTIDISPLAY-SPACES-RELIABILITY-2026-11-13.md). The scope above records the earlier build's evidence.

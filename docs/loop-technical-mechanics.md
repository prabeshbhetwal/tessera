# Loop: how each capability works on macOS

Date: 2026-10-03

This is a teardown of Loop, written so we can build our own version independently. It is in our own words and contains no Loop source code (Loop is GPL-3.0). Paths are relative to `loop/Loop/`.

Abbreviations used below:
- **AX**: the macOS Accessibility API, which is how one app reads and moves another app's windows.
- **SPI**: a private Apple API. It can disappear or change in any macOS update.
- **TCC**: the macOS permission system (Accessibility, Input Monitoring and so on).

---

## 1. Finding the target window

### Frontmost window
Loop reads `NSWorkspace.frontmostApplication`, then asks that app for its AX focused window.

If the pid comes back as 0 or less, it falls back to `kAXFocusedApplicationAttribute` on the system-wide AX element.

### Window under the cursor
Loop tries three methods, in this order:
1. **`SLSFindWindowByGeometry`** (SPI). Fast, and it avoids a deadlock when the window found is Loop's own.
2. **`AXUIElementCopyElementAtPosition`**, then that element's `AXWindow` attribute.
3. **`CGWindowListCopyWindowInfo`**, scanning for a window whose frame contains the point.

### Matching AX windows to window IDs
- **AX window → CGWindowID:** `_AXUIElementGetWindow` (SPI).
- **CGWindowID → AX window:** list the pid's `AXWindows` and match on position + size. Two windows with identical frames need an extra tie-break.

### Skipping things that are not real windows
Loop filters out:
- sheets
- windows whose level is outside normal…popup (`SLSGetWindowLevel`)
- windows that have a parent window
- windows with invalid `SLSWindowTags`
- PiP and Notification Center, via a bundle-ID block list
- the Safari OTP window on macOS 26

**Pitfall:** when the `SLSWindowTags` symbols fail to load, Loop rejects every window. A missing SPI must mean "skip this check", never "reject".

### Our plan
- Use public AX + CGWindowList.
- Load `_AXUIElementGetWindow` with `dlsym`.
- Treat SLS hit-testing as an optional speed-up only.

---

## 2. Moving and resizing windows

### How Loop does it
- Set `kAXPosition` / `kAXSize` with `AXUIElementSetAttributeValue`.
  - AX coordinates start at the **top-left**, relative to `NSScreen.screens[0]`.
  - AppKit coordinates start at the **bottom-left**.
  - Converting between them is a Y flip.
- **Order of operations:**
  - Same screen: set position, then size.
  - Moving to another screen: set size, then position, then size again, so the old screen does not clamp the window.
  - If the result is wrong, retry once.
- **Apps with size limits** (minimum size, fixed aspect ratio): re-anchor the size the app actually accepted to the edges you were aiming for.
- **`AXEnhancedUserInterface`** (turned on by VoiceOver and Electron apps) makes resizes animate and drift. Loop turns it off, sets the frame, then turns it back on.
- **Animation:** an `NSAnimation` that writes AX position and size every frame, over 0.3 s with ease-out. It is capped by AX round-trip speed.
- **Native tiling on macOS 15+:** Loop finds the window's menu item with AX identifier `_zoomLeft:`, `_zoomFill:` and so on, and triggers it with `AXPress`. It reads `com.apple.WindowManager` `TiledWindowSpacing` to match the system's gaps.
- **Loop's own windows:** AX cannot target your own process, so Loop uses `NSWindow.setFrame`.

### Our plan
- Call `AXUIElementSetMessagingTimeout` on every app element.
- Read the frame back once at the end, not on every animation frame.
- Keep a per-app table of quirks.

---

## 3. Global keyboard and mouse input

### Event taps
- `CGEvent.tapCreate` with `.cgSessionEventTap` and `.headInsertEventTap`.
- **Active taps** (can swallow events): `keyDown`, `keyUp`, `flagsChanged`, and left-click while the menu is open.
- **Passive taps** (listen only): mouse moved, mouse dragged, middle-click.
- All taps run on one dedicated thread with its own CFRunLoop. A dummy source keeps that run loop alive.

### Timeouts
- On `tapDisabledByTimeout` or `tapDisabledByUserInput`, Loop re-enables the tap.
- More than 5 restarts within 2 s triggers a 2 s backoff.
- Teardown: invalidate the port on the tap thread before releasing the refcon.

### Detecting the trigger key
- Track pressed keycodes in a set.
- Left vs right modifier: the `NX_DEVICE*KEYMASK` bits.
- Fn: `maskSecondaryFn`. Arrow, Delete and Help keys report the Fn flag even when Fn is not held, so it is stripped for those keys.
- Globe/emoji key: swallowed if the mouse moved, otherwise passed through to the system.
- To suppress an event, return nil from an active tap.
- **System shortcut conflicts:** `CopySymbolicHotKeys` (Carbon) lists the enabled system shortcuts. If a key matches one, Loop passes the event through and closes the menu.

### Permissions needed
Accessibility. Input Monitoring (TCC "ListenEvent") may also apply.

### Our plan
- Tap callbacks never block.
- Copy each event into a value, then hop to the main actor once.

---

## 4. Overlay windows (radial menu and preview)

### Panel setup
- An `NSPanel` with `.borderless` and `.nonactivatingPanel`, `ignoresMouseEvents`, and `.canJoinAllSpaces`.
- Clear background, no shadow, shown with `orderFrontRegardless`.
- `hasKeyAppearance` / `hasActiveAppearance` are overridden so materials render as active.
- **Window levels:** radial menu at `.screenSaver`, preview one level below it.
- **Content:** SwiftUI in an `NSHostingView`.
  - On macOS 26+, `.glassEffect`.
  - `GlassEffectContainer` with the materialize transition crashed.

### Tracking the cursor
The menu is fixed at the point where the trigger was pressed. Passive mouse-move events give an angle and distance from that origin, which selects a wedge. The origin is clamped near screen edges.

### Preview
The preview panel covers the target screen and jumps to another screen when the target changes.

### Our plan
- One reusable panel per display.
- `CAShapeLayer` for the wedges, so a mouse move costs no SwiftUI work.

---

## 5. Drag-to-snap

### How Loop does it
- Passive tap on `leftMouseDragged` / `leftMouseUp`.
- **First drag event:** find the window under the cursor and save its frame.
- **Later drag events:** compare the window's AX frame with the saved one.
  - Origin changed: it is a move.
  - Size changed: it is a resize, which Loop ignores.
- **Snap zones:** the screen frame minus a `snapThreshold` inset. At the top, the inset is at least half the menu bar height.
- The action is applied on mouse-up, with haptics through `NSHapticFeedbackManager`.
- **Mission Control suppression:** when the cursor is at the very top pixel, warp it down 1 px with `CGWarpMouseCursorPosition`.
- **Detecting Mission Control:** look for Dock AX children with identifiers `mc` or `appexpose`, using a 0.1 s timeout.

### Our plan
Subscribe to `kAXMovedNotification` instead of reading the window frame on every drag event.

---

## 6. Trackpad gestures

### How Loop does it
- Uses the private MultitouchSupport framework, via Loop's Subsurface package: `MTDeviceCreateList`, `MTRegisterContactFrameCallback`, `MTDeviceStart`.
- **Blocking system gestures:**
  - Undocumented `CGEventType` 30 (dockControl), with fields 110, 123, 124, 129 and 132.
  - Gestures limited to the titlebar wait up to 40 ms for a hit test.
  - Every Dock stroke must be ended, or the Dock gets stuck.
  - Scroll deltas are zeroed while a gesture is active.

### Our plan
Most fragile area. Ship it last, behind a flag.

---

## 7. Spaces, focus and stash

### Moving a window to another Space (macOS 14+)
Use the private ObjC classes `SLSBridgedMoveWindowsToManagedSpaceOperation`, `SLSBridgedCopySpacesForWindowsOperation` and `SLSBridgedCopyManagedDisplaySpacesOperation`, via `performWithWMBridgeDelegate`.

The older `CGSMoveWindowsToManagedSpace` stopped working on other apps' windows around 14.5 (unverified).

### Focusing a window
1. `_SLPSSetFrontProcessWithOptions`
2. `SLPSPostEventRecordTo`, sending a synthetic mouse-down. The point must be finite and far away from the window.
3. `AXRaise`.

### Stash
Public AX only. Move the window mostly off-screen, reveal it on mouse proximity, and persist its frame so it can be restored.

---

## 8. Permissions

- **Check:** `AXIsProcessTrusted`. **Prompt:** `AXIsProcessTrustedWithOptions(prompt)`.
- **Watch for changes:** the distributed notification `com.apple.accessibility.api`. Wait 250 ms before re-reading, because the value lags.
- **Reset a stale entry:** `tccutil reset Accessibility|ListenEvent <bundle>`.
- **Wallpaper-based accent colour:** Loop captures the wallpaper window with `SLSHWCaptureWindowList` (SPI).

### Our plan
- Onboarding asks for Accessibility only.
- For a wallpaper accent, use `NSWorkspace.desktopImageURL` (public, no screen-capture permission).

---

## 9. App lifecycle

| Area | What Loop does | Our plan |
|---|---|---|
| Dock icon | Switches activation policy between `.regular` and `.accessory` at runtime, which makes the Dock icon flash | `LSUIElement=YES`; switch to `.regular` only while Settings is open |
| Menu bar | SwiftUI `MenuBarExtra` | Same |
| Launch at login | `SMAppService.mainApp` | Same |
| Single instance | A "terminate" distributed notification | Check `NSRunningApplication` for our own bundle ID |
| Updates | A root helper (`SMJobSubmit`) plus XPC | Sparkle 2 with EdDSA signing; no root helper |

---

## 10. macOS version constraints

| macOS | Matters for |
|---|---|
| 14 | Spaces SPI. `SLPSPostEventRecordTo` needs a larger buffer from 14.7.4. |
| 15 | Native tiling menu items and tiling defaults. **Our minimum.** |
| 26 | Liquid Glass. Corner radii via `SLSWindowIteratorGetResolvedCornerRadii`. `SLSWindowIteratorGetAttributes` is broken from 26.3. |
| 27 | Wallpaper window owner changed. The synthetic focus click can trigger a resize. |

---

## Recommended stack for our app

### Language and concurrency
- Swift 6 language mode, with complete strict concurrency checking.
- **AX calls:** one dedicated serial actor. AX is synchronous IPC and must not block the UI.
- **UI:** the main actor.
- **Event-tap callbacks:** `nonisolated`, passing Sendable values.

### Public frameworks
AX, CGEventTap, CGWindowList, AppKit (`NSPanel`, CALayer), SwiftUI for settings, `SMAppService`, Sparkle.

### Private APIs worth using
All loaded with `dlsym`, all optional:
- `_AXUIElementGetWindow`
- `_SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo`
- `SLSGetWindowLevel`
- the SLSBridged Space operations
- MultitouchSupport, only if we ship gestures

### Private APIs to avoid
`SLSWindowTags` parsing, `SLSHWCaptureWindowList`, background-blur SPI, icon-cache SPI, `@_silgen_name`, root helpers.

---

## The 5 hardest problems

1. **Resizing reliably in difficult apps** (Electron, Java, fixed-aspect windows, hung apps).
   Fix: messaging timeout, toggle Enhanced UI, size → position → size, re-anchor, read back once, keep a quirk table.
2. **Concurrency between the event tap, AX calls and the UI.**
   Fix: one serial AX actor, immutable events, a callback that never blocks, backoff on tap timeouts.
3. **Identifying the target window correctly.**
   Fix: `_AXUIElementGetWindow`, check role/subrole and window level, test against a table of real apps.
4. **Gestures without breaking the Dock.**
   Fix: defer to a later phase, and always end every Dock stroke.
5. **Coordinates across multiple displays.**
   Fix: one well-tested conversion module, refreshed on `didChangeScreenParametersNotification`.

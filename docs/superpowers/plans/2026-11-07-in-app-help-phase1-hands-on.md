# In-app help phase 1: hands-on checks

These are the checks no automated test can cover. Run them on the built app. First choose **Settings › General › Help › Show Tips Again**, then open Dia, Claude and Codex on the CHG90.

## A. The coach flow (most important)
1. Press ⌃⌥T with no split saved. You should get "Tiled in equal shares" with the full coach: the screen dims, the three windows are spotlighted, and a card appears.
2. Choose **Show Me More**. The edge between Dia and Claude should pulse. Click Dia's edge and drag it: the card stays open. About a second later step 3 appears ("Claude and Codex followed"), with the spotlight on where the windows ended up.
3. Choose **Undo** in step 3. The windows should go back to equal shares, with no split left in Settings › Splits.
4. Teach a split, then press ⌃⌥T again. No coach appears, because you've already seen it. Now press ⌃⌥/:
   - "Tiled with your split… on 7 Nov…" opens.
   - Tab and Return work on the card.
   - ← and → step through earlier events.
   - Esc closes it.
   - No shortcut receipt flashes.
5. Choose **Tile Evenly Instead**. You should get equal thirds, and Settings › Splits should still list the split.
6. Close Codex while a step 1 card is open, then click **Tile Evenly Instead**. The card should say "These windows have changed since then." and nothing should move.
7. Press ⌃⌥T, then press ⌃⌥← on another window, then click **Undo** on the older card. The card should say "These windows have changed since then." and nothing should be undone.
8. Choose **Skip** on the "Try it" step. The card should close and nothing should change.
9. Choose **Forget This Split** on "Saved as your split". It should confirm the split is forgotten. Its **Undo** should bring the split back in Settings › Splits and retile the windows to it.
10. Run `tessera tile` in Terminal. No coach should appear, but ⌃⌥/ should still explain what happened.
11. Overlap two windows and drag one. A light card, "Not saved as a split", should appear, at most once per day for that reason.

## B. It must never get in the way
12. Type in TextEdit while an auto card shows. Every character should land, and the first key should fade the card. On the "Try it" step, typing leaves the card up; Esc closes it.
13. Clicks and drags pass through the dim to the real windows.
14. Card buttons work on the first click without Tessera taking focus. The front app's name stays in the menu bar.
15. Leave a "Try it" step alone. It should close by itself after about 60 s, unless the pointer is resting on the card.

## C. Looks and settings
16. The dim and spotlight line up with the real windows on both the MacBook (Retina) and the CHG90.
17. The card's rounded corners clip its blurred background cleanly. The primary button shows in the accent colour on an auto card.
18. **Dim the screen behind tips** turned off: no card dims the screen, and the "Try it" step shows only the pulsing edge.
19. Changing Overlay › Dimming colour or strength changes the coach's dim.
20. With Reduce Motion on, cards still fade but the edge doesn't pulse.
21. Choose **Don't show tips** on a card. General › Help › "Show tips on their own" should turn off, and ⌃⌥/ should still work.
22. **Show Tips Again** shows "Tips will show again." The note should be gone after you switch panes.
23. The menu bar has **What Just Happened?** under the status line. Hiding it in General › Menu bar should leave the separator correct.
24. With VoiceOver on, an auto card is read aloud as "title. body".
25. A keyable card (⌃⌥/) closes when you switch to a third app, but not when you go back to the app you came from.
26. After ⌃⌥T, the "Tiled 3 windows" message and the coach card appearing together shouldn't look too busy on the 14" display.
27. The Console shows no Auto Layout warnings from the card.

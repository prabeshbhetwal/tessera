#!/usr/bin/env bash
# Native checks of the window actor, split watchers and workspace recovery, with an isolated AX frame boundary:
# no desktop windows are moved.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="${TESSERA_RELIABILITY_SCRATCH:-$HOME/Library/Caches/tessera-build/reliability}"
xcrun swift build --target TesseraCore --package-path Packages/TesseraCore --scratch-path "$SCRATCH" --jobs 2
PRODUCTS="$(xcrun swift build --show-bin-path --package-path Packages/TesseraCore --scratch-path "$SCRATCH")"
MODULES="$PRODUCTS"; [[ ! -d "$PRODUCTS/Modules" ]] || MODULES="$PRODUCTS/Modules"
OBJECT="$(find "$SCRATCH" -type f \( -name 'RingFeedback.swift.o' -o -name 'RingFeedback.o' \) -print -quit)"
xcrun swiftc -parse-as-library -swift-version 6 -I "$MODULES" \
  Tessera/Services/WindowService.swift Tessera/Services/WindowService+Anchoring.swift Tessera/Services/WindowService+Undo.swift Tessera/Services/WindowService+PlacementHistory.swift \
  Tessera/Services/WindowService+Placement.swift Tessera/Services/WindowService+Visible.swift Tessera/Services/WindowService+Failures.swift Tessera/Services/WindowMutationContext.swift Tessera/Services/WindowTopology.swift \
  Tessera/Services/SPI+Workspaces.swift \
  Tessera/Services/WindowLifecycleMonitor.swift Tessera/Services/AX.swift Tessera/Services/WindowUndoHistory.swift Tessera/Services/SPI.swift \
  Tessera/Services/DisplayService.swift Tessera/Services/SplitWatcher.swift Tessera/Services/SplitWatcher+Baseline.swift Tessera/Services/SplitWatcher+Save.swift \
  Tessera/Services/SplitWatchers.swift Tessera/Services/SplitWatchers+Rearm.swift \
  Tessera/Services/SplitWorkspaceStore.swift Tessera/Services/SplitWatchers+Contexts.swift Tessera/Services/SplitWatchers+Resume.swift \
  Tessera/Services/SplitWatchers+Startup.swift Tessera/Services/SplitWatchers+Notifications.swift \
  Tessera/Services/SplitWatchers+Manual.swift \
  Tessera/Services/SplitWatchers+Configuration.swift Tessera/Services/SplitWatchers+Convergence.swift Tessera/Services/WindowLayoutPolicy.swift \
  Tessera/Services/SplitWatchers+Fill.swift Tessera/Services/SplitWatchers+Join.swift Tessera/Services/MinimisedWindows.swift \
  Tessera/Services/WindowService+Together.swift Tessera/Help/HelpEvent+App.swift \
  Tessera/App/SettingsModel.swift \
  scripts/verify-window-reliability.swift scripts/verify-split-lifecycle.swift scripts/verify-window-context.swift scripts/verify-workspace-recovery.swift \
  scripts/verify-window-policies.swift scripts/verify-workspace-transactions.swift \
  "$(dirname "$OBJECT")"/*.o -o "$SCRATCH/verify-window-reliability"
"$SCRATCH/verify-window-reliability"

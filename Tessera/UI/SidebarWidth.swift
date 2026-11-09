import AppKit
import SwiftUI

/// Puts a width range on the split view's sidebar that holds this view, and moves the divider into it.
/// SwiftUI applies `navigationSplitViewColumnWidth` only when it builds the split, so a range that changes later
/// (the Settings sidebar narrowing to icons) has to reach AppKit's sidebar item directly. Rebuilding the split
/// instead would reset the detail column (its scroll position and any text being typed).
struct SidebarWidth: NSViewRepresentable {
    let range: ClosedRange<CGFloat>

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let range = range
        // After this pass, once the view is inside the split.
        Task { @MainActor in
            guard let split = Self.splitView(holding: view),
                  let item = (split.delegate as? NSSplitViewController)?.splitViewItems.first,
                  let sidebar = split.arrangedSubviews.first else { return }
            item.minimumThickness = range.lowerBound
            item.maximumThickness = range.upperBound
            let width = sidebar.frame.width
            guard !range.contains(width) else { return }
            split.setPosition(min(max(width, range.lowerBound), range.upperBound), ofDividerAt: 0)
        }
    }

    private static func splitView(holding view: NSView) -> NSSplitView? {
        var current = view.superview
        while let next = current {
            if let split = next as? NSSplitView { return split }
            current = next.superview
        }
        return nil
    }
}

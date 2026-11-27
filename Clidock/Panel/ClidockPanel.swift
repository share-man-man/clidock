// Modified for Clidock on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import OSLog

@MainActor
final class ClidockPanel: NSPanel {
    /// Records repairs to a history window's Space membership.
    private static let logger = Logger(clidockCategory: "HistoryPanel")

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        // The content draws its own shadow (`PanelSlideView`) so it can slide
        // with the content; the window shadow could only follow the window.
        hasShadow = false
        // Clidock stays inactive while the panel is up (it's a non-activating
        // panel), and AppKit hides tooltips for inactive apps by default, so
        // every `.help` in the panel would never show.
        allowsToolTipsWhenApplicationIsInactive = true

        minSize = NSSize(width: 100, height: 200)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 800)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Whether macOS lists this window among this app's windows on the active Spaces.
    /// An order-front request alone sets `isVisible` even if the window lost its Space.
    var isListedOnActiveSpace: Bool {
        // Query this panel alone. A fully covered window still counts as ordered on screen.
        guard windowNumber > 0 else { return false }
        guard let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(windowNumber)) as? [[String: Any]] else {
            return isVisible && isOnActiveSpace
        }
        return windows.first?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    /// Repairs a presentation that WindowServer still omits after ordering has settled.
    /// - Returns: A newly ordered window sharing the original content when a repair was needed.
    func replaceIfMissingFromActiveSpace() -> ClidockPanel? {
        guard !isListedOnActiveSpace else { return nil }

        // Reordering the same window keeps its stale Space membership. A new window
        // at the requested frame gets a fresh assignment from WindowServer.
        let replacement = ClidockPanel(contentRect: contentRect(forFrameRect: frame))
        // Keep the hosting tree, including its SwiftData queries and search state.
        let content = contentView
        orderOut(nil)
        contentView = nil
        replacement.contentView = content
        replacement.orderFrontRegardless()
        Self.logger.notice("Replaced history window missing from the active Space")
        return replacement
    }

    /// AppKit nudges ordinary windows back inside a screen's usable area. The
    /// panel is deliberately parked off the bottom edge while it animates, and
    /// the default behaviour both shifts that position and re-homes the panel
    /// to a neighbouring display. Place the panel exactly where asked.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

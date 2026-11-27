// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Monochrome Popback mark that follows the menu bar appearance.
@MainActor
enum MenuBarIconImage {
    /// Cached status item image for the running build configuration.
    static let current = make(badge: Bundle.main.menuBadge)

    /// Composes the badge and icon into a single template for the native status item.
    /// - Parameter badge: Optional build label to draw to the right of the icon.
    private static func make(badge: String?) -> NSImage {
        // The vector asset supplies the menu bar height and the template for unbadged builds.
        let icon = NSImage(named: DesignTokens.MenuBar.iconAssetName) ?? NSImage()
        guard let badge else { return icon }
        // The status item must reserve enough space for the full label.
        let iconSize = icon.size
        // Round up to avoid clipping the last glyph at non-Retina scales.
        let size = NSSize(width: ceil(iconSize.width + badgeGap + badgeText(badge).size().width),
                          height: iconSize.height)
        // AppKit can invoke the drawing handler off the main actor and at a different display scale.
        let image = NSImage(size: size, flipped: false) { _ in
            NSImage(named: DesignTokens.MenuBar.iconAssetName)?.draw(in: NSRect(origin: .zero, size: iconSize))
            // Center the label vertically against the mark.
            let text = badgeText(badge)
            text.draw(at: NSPoint(x: iconSize.width + badgeGap, y: (iconSize.height - text.size().height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Space in points between the icon and its badge.
    nonisolated private static let badgeGap: CGFloat = 1

    /// Formats a badge for monochrome template rendering.
    /// - Parameter badge: Build label supplied by the app bundle.
    nonisolated private static func badgeText(_ badge: String) -> NSAttributedString {
        NSAttributedString(string: badge, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                                                       .foregroundColor: NSColor.black])
    }
}

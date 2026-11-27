// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Marks what this running Popback puts on the clipboard, so the clipboard
/// monitor can tell its own writes from the user's copies by content rather
/// than by timing. A timing-based skip swallowed a copy the user made between
/// two polls.
enum OwnPasteboardWrite {
    /// A per-launch marker lets other Macs using Universal Clipboard record these copies.
    nonisolated static let type = NSPasteboard.PasteboardType(
        AppIdentity.namespace + ".own." + UUID().uuidString
    )

    /// Tags the clipboard's current contents as written by this Popback.
    /// Call after the write is complete, so the tag can't reorder its items.
    /// - Parameter pasteboard: the pasteboard just written to
    @MainActor
    static func mark(_ pasteboard: NSPasteboard) {
        pasteboard.setData(Data(), forType: type)
    }

    /// Whether the clipboard's current contents came from this Popback.
    /// Reading the types never asks a data provider for promised data.
    /// - Parameter pasteboard: the pasteboard to check
    @MainActor
    static func isOwn(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(type) == true
    }
}

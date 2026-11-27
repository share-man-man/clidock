// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices

/// Optional "paste into the active app": after a clip is copied and the panel
/// closes, Popback presses ⌘V for the user. Off by default. Posting a key
/// event needs Accessibility permission, and without it the clip is only
/// copied, exactly as when the setting is off.
@MainActor
enum DirectPaste {
    nonisolated static let enabledDefaultsKey = "pasteIntoActiveApp"

    /// Stamped on the ⌘V events Popback posts, so they can be told apart from
    /// the user's own ⌘V.
    nonisolated static let syntheticEventMarker: Int64 = 0x506F_7062_6163_6B // "Popback"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKey)
    }

    /// Reads the Accessibility grant live. `CGPreflightPostEventAccess` kept
    /// answering true inside a running process after the grant was removed in
    /// System Settings, so the settings warning never appeared and ⌘V was
    /// silently dropped. The Accessibility grant alone is enough to post it.
    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Whether the next paste should be followed by ⌘V.
    static var isReady: Bool {
        isEnabled && hasPermission
    }

    /// Requests Accessibility access when the user explicitly enables simulated key presses.
    @discardableResult
    static func requestPermission() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Sends ⌘V to whichever app has keyboard focus. Call only after the
    /// panel is off screen, or the panel itself receives it.
    @discardableResult
    static func sendPasteShortcut() -> Bool {
        sendCommandShortcut(keyCode: PasteKeyCode.current(), suppressesLocalKeys: true)
    }

    /// Sends ⌘C to whichever app has keyboard focus.
    @discardableResult
    static func sendCopyShortcut() -> Bool {
        // The queue shortcut is already let go (`SelectionCopy.waitForRelease`),
        // so nothing held can mix in, and the user may already be pressing ⌘C.
        sendCommandShortcut(keyCode: PasteKeyCode.currentCopy(), suppressesLocalKeys: false)
    }

    /// Sends Command plus a key to whichever app has keyboard focus.
    /// - Parameters:
    ///   - keyCode: the key pressed with Command
    ///   - suppressesLocalKeys: drop the user's own key presses for a moment
    ///     (0.25 s by default) after posting, so keys still held can't mix in.
    ///     Off when the user may be typing right away.
    /// - Returns: whether the events were posted
    private static func sendCommandShortcut(keyCode: CGKeyCode, suppressesLocalKeys: Bool) -> Bool {
        guard hasPermission else { return false }

        /// Source of the posted events.
        let source = CGEventSource(stateID: .combinedSessionState)
        if suppressesLocalKeys {
            // Keep keys the user is still holding from mixing into the shortcut.
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
        } else {
            // No suppression interval: the user's next keys go through at once.
            source?.localEventsSuppressionInterval = 0
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        // Include the left Command device bit; some apps ignore a Command flag
        // that no physical side key accounts for.
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x0000_0008)
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return true
    }
}

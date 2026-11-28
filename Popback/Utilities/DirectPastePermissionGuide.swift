// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only

/// Tracks when to surface Accessibility permission guidance for Direct Paste.
///
/// The guidance appears once per revocation: if the user turns off
/// Accessibility in System Settings while "Paste into the Active App" stays on,
/// the panel shows a dismissible banner and the first fallback paste shows an
/// alert. Restoring permission or re-enabling Direct Paste resets the state so
/// a future revocation prompts again.
struct DirectPastePermissionGuide: Equatable, Sendable {
    private(set) var isBannerDismissed = false
    private(set) var hasPromptedForRevocation = false

    /// Whether Direct Paste is enabled but blocked by missing Accessibility access.
    func needsAttention(isEnabled: Bool, hasPermission: Bool) -> Bool {
        isEnabled && !hasPermission
    }

    /// Resets dismissal and one-time prompt flags once the issue is resolved.
    mutating func sync(isEnabled: Bool, hasPermission: Bool) {
        if !needsAttention(isEnabled: isEnabled, hasPermission: hasPermission) {
            reset()
        }
    }

    /// Clears dismissal and one-time prompt flags so guidance can appear again.
    mutating func reset() {
        isBannerDismissed = false
        hasPromptedForRevocation = false
    }

    /// Whether the History panel should show its inline permission banner.
    func shouldShowPanelBanner(isEnabled: Bool, hasPermission: Bool) -> Bool {
        needsAttention(isEnabled: isEnabled, hasPermission: hasPermission) && !isBannerDismissed
    }

    /// Dismisses the panel banner for the current revocation and avoids
    /// immediately following up with a modal alert on the next paste.
    mutating func dismissPanelBanner() {
        isBannerDismissed = true
        hasPromptedForRevocation = true
    }

    /// Consumes the one-time alert budget for a paste that had to fall back to
    /// copy-only because Accessibility permission is off.
    mutating func consumePastePrompt(isEnabled: Bool, hasPermission: Bool) -> Bool {
        sync(isEnabled: isEnabled, hasPermission: hasPermission)
        guard needsAttention(isEnabled: isEnabled, hasPermission: hasPermission),
              !hasPromptedForRevocation else {
            return false
        }
        hasPromptedForRevocation = true
        return true
    }
}

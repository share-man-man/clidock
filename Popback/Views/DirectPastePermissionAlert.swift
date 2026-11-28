// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Native warning dialog shown once per Accessibility revocation when a direct
/// paste has to fall back to copying.
@MainActor
enum DirectPastePermissionAlert {
    static func present(
        onOpenSettings: () -> Void,
        onTurnOff: () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Direct Paste Needs Accessibility Permission")
        alert.informativeText = String(
            localized: "The clip was copied to your clipboard—press \u{2318}V to paste it. Turn on Accessibility for \(Bundle.main.appName) in System Settings to paste automatically, or turn off Paste into the Active App."
        )
        alert.addButton(withTitle: String(localized: "Open Accessibility Settings\u{2026}"))
        alert.addButton(withTitle: String(localized: "Turn Off Direct Paste"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            onOpenSettings()
        case .alertSecondButtonReturn:
            onTurnOff()
        default:
            break
        }
    }
}

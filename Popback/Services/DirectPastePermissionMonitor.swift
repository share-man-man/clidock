// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import AppKit

/// Tracks the live Accessibility grant and "Paste into the Active App" toggle
/// across all UI surfaces, debouncing system TCC notifications so rapid toggles
/// never read a stale pre-commit value into HIServices's cache.
@MainActor
@Observable
final class DirectPastePermissionMonitor {
    /// Live Accessibility trust state.
    private(set) var hasPermission = DirectPaste.hasPermission
    /// Mirror of Settings > Pasting > Paste into the Active App for SwiftUI observation.
    private(set) var isEnabled = DirectPaste.isEnabled
    private var guide = DirectPastePermissionGuide()

    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Whether the next paste should automatically send ⌘V.
    var isReady: Bool {
        isEnabled && hasPermission
    }

    /// Whether Direct Paste is enabled while Accessibility permission is off.
    var needsAttention: Bool {
        guide.needsAttention(isEnabled: isEnabled, hasPermission: hasPermission)
    }

    /// Whether the History panel should show its inline Accessibility warning bar.
    var showsPanelBanner: Bool {
        guide.shouldShowPanelBanner(isEnabled: isEnabled, hasPermission: hasPermission)
    }

    /// Starts observing system Accessibility notifications and preference changes.
    func start() {
        guard observers.isEmpty else { return }

        // macOS broadcasts this distributed notification a few milliseconds before
        // `tccd` commits the new record; debounce before querying `AXIsProcessTrusted()`.
        let axObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSettleRefresh()
            }
        }

        let activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }

        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled != DirectPaste.isEnabled else { return }
                self.refresh(force: true)
            }
        }

        observers = [axObserver, activeObserver, defaultsObserver]
        refresh(force: true)
    }

    /// Syncs the setting and live Accessibility grant.
    /// - Parameter force: Pass `false` for passive UI hooks so they do not query
    ///   `AXIsProcessTrusted()` mid-debounce while `tccd` is still committing.
    func refresh(force: Bool = false) {
        if !force, settleTask != nil {
            return
        }
        let enabled = DirectPaste.isEnabled
        let trusted = DirectPaste.hasPermission
        if isEnabled != enabled {
            isEnabled = enabled
        }
        if hasPermission != trusted {
            hasPermission = trusted
        }
        var updated = guide
        updated.sync(isEnabled: enabled, hasPermission: trusted)
        if updated != guide {
            guide = updated
        }
    }

    /// Consumes the one-time fallback alert budget using the current synced state.
    func consumePastePrompt() -> Bool {
        guide.consumePastePrompt(isEnabled: isEnabled, hasPermission: hasPermission)
    }

    /// Hides the panel's inline warning bar for the current revocation.
    func dismissPanelBanner() {
        guide.dismissPanelBanner()
    }

    /// Turns off "Paste into the Active App" and clears any warning state.
    func disableDirectPaste() {
        DirectPaste.setEnabled(false)
        refresh(force: true)
    }

    private func scheduleSettleRefresh() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.settleTask = nil
            self.refresh(force: true)
        }
    }
}

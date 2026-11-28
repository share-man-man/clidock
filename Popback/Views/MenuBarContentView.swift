// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import SwiftData
import KeyboardShortcuts

/// Native menu commands for recent copies, panel shortcuts and app settings.
@MainActor
struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(AppState.self) private var appState
    @Query(sort: \ClipboardItem.copiedAt, order: .reverse)
    private var recentItems: [ClipboardItem]

    var body: some View {
        // Put the configuration above recent copies, where it is visible as soon as the menu opens.
        if let banner = Bundle.main.menuBanner {
            Text(verbatim: banner)
            Divider()
        }

        if appState.directPastePermission.needsAttention {
            Button {
                appState.openDirectPasteAccessibilitySettings()
            } label: {
                Label("Direct Paste Needs Accessibility\u{2026}", systemImage: "exclamationmark.triangle.fill")
            }
            Divider()
        }

        Section("Recent Copies") {
            if recentItems.isEmpty {
                Text("No clipboard history")
            } else {
                ForEach(recentItems.prefix(ClipboardMonitor.recentMenuLimit)) { item in
                    MenuBarItemRow(item: item)
                }
            }
        }

        Divider()

        Button("Open History") {
            appState.openPanel()
        }
        .globalKeyboardShortcut(.toggleHistoryPanel)

        Button(appState.clipQueue.isActive ? "End Clip Queue" : "Start Clip Queue") {
            appState.toggleClipQueue()
        }
        .globalKeyboardShortcut(.toggleClipQueue)

        Toggle("Clipboard Monitoring", isOn: Binding(
            get: { appState.clipboardMonitor.isMonitoring },
            set: { _ in appState.clipboardMonitor.toggle() }
        ))

        Divider()

        Button {
            appState.requestedSettingsPane = .about
            openSettings()
            SettingsWindowFront.bring()
            if case .available = appState.updater.state {
                // Already fetched; show the available update directly in Settings > About.
            } else {
                appState.updater.checkForUpdates(userInitiated: true)
            }
        } label: {
            if let version = appState.updater.availableUpdate?.version.description {
                Label("Update Available (\(version))…", systemImage: "arrow.down.circle.fill")
            } else {
                Text("Check for Updates…")
            }
        }

        Button("Send Feedback…") {
            NSWorkspace.shared.open(AppIdentity.issuesURL)
        }

        Divider()

        Button("Settings…") {
            openSettings()
            SettingsWindowFront.bring()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit \(Bundle.main.appName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

}

@MainActor
private struct MenuBarItemRow: View {
    /// Clipboard entry represented by this menu command.
    let item: ClipboardItem
    @Environment(AppState.self) private var appState

    /// Menus grow to fit their longest item, so long clips are cut here.
    private static let titleLimit = 42

    var body: some View {
        Button {
            appState.clipQueue.stop()
            appState.pasteService.paste(item: item)
        } label: {
            Image(systemName: item.contentType.systemImage)
            Text(verbatim: title)
            Text(verbatim: subtitle)
        }
    }

    private var title: String {
        // Use a localized label for clips without a textual preview.
        let text: String
        switch item.contentType {
        case .plainText, .richText, .html, .url:
            text = item.textContent ?? "…"
        case .image:
            text = String(localized: "Image")
        case .fileURL:
            text = item.textContent ?? String(localized: "File")
        case .color:
            text = item.textContent ?? String(localized: "Color")
        case .unknown:
            text = String(localized: "Unknown")
        }
        // Keep the first nonempty line within the native menu's width.
        let line = text.drop(while: \.isWhitespace).prefix(Self.titleLimit + 1).prefix(while: { !$0.isNewline })
        guard !line.isEmpty else { return "…" }
        return line.count > Self.titleLimit ? String(line.prefix(Self.titleLimit)) + "…" : String(line)
    }

    private var subtitle: String {
        [item.sourceAppName, RelativeTimeFormatter.string(for: item.copiedAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

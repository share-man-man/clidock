// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct PastingSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage(PasteService.alwaysPlainTextDefaultsKey) private var alwaysPastePlainText: Bool = false
    @AppStorage(DirectPaste.enabledDefaultsKey) private var pasteIntoActiveApp: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $alwaysPastePlainText) {
                    Text("Always Paste as Plain Text")
                    Text("Removes fonts, colors, and links from rich text and HTML clips, pasting only the text.")
                        + Text(verbatim: " ")
                        + Text("Hold \u{21e7} while pasting to switch for a single paste.")
                }

                Toggle(isOn: $pasteIntoActiveApp) {
                    Text("Paste into the Active App")
                    Text("Clicking a clip or pressing Return pastes it where you were typing. When off, the clip is only copied.")
                }
                .onChange(of: pasteIntoActiveApp) { _, isOn in
                    if isOn, !DirectPaste.hasPermission {
                        DirectPaste.requestPermission()
                    }
                    appState.directPastePermission.refresh(force: true)
                }

                if pasteIntoActiveApp, !appState.directPastePermission.hasPermission {
                    LabeledContent {
                        Button("Open Accessibility Settings\u{2026}") {
                            DirectPaste.openAccessibilitySettingsWithPrompt()
                        }
                    } label: {
                        Label("Accessibility permission is off, so clips are only copied.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("If \(Bundle.main.appName) isn't in the list, add it with the + button.")
                    }
                }
            }
        }
        // DirectPastePermissionMonitor updates live via the debounced
        // `com.apple.accessibility.api` notification; avoid a tight polling loop
        // that could query `AXIsProcessTrusted()` mid-commit and poison HIServices's cache.
        .onAppear {
            appState.directPastePermission.refresh()
        }
    }
}

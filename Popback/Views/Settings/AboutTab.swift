// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@MainActor
struct AboutTab: View {
    @Environment(AppState.self) private var appState
    @State private var didResetPromptsAndCache = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text("Version \(appVersion) (\(buildNumber))")
                } label: {
                    Text(verbatim: Bundle.main.appName)
                    Text("A simple clipboard manager for macOS.")
                }

                Button("View Releases…") {
                    NSWorkspace.shared.open(AppIdentity.releasesURL)
                }

                Button("Show Welcome Tour…") {
                    // The tour uses the current installation's store.
                    guard let container = appState.modelContainer else { return }
                    OnboardingWindowController.shared.show(appState: appState, modelContainer: container)
                }
            }

            Section("Maintenance") {
                LabeledContent {
                    Button("Reset") {
                        appState.resetPromptsAndCache()
                        didResetPromptsAndCache = true
                    }
                } label: {
                    Text("Reset Prompts & Cache")
                    Text("Shows dismissed tips again and clears temporary cache. History, pinboards, and settings are kept.")
                    if didResetPromptsAndCache {
                        Label("Prompts and cache were reset.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI

@MainActor
struct AboutTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppUpdateDefaults.autoCheckKey) private var automaticallyCheckForUpdates = false
    @State private var didResetPromptsAndCache = false

    private var updater: AppUpdater { appState.updater }

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

                Button("Show Welcome Tour…") {
                    // The tour uses the current installation's store.
                    guard let container = appState.modelContainer else { return }
                    OnboardingWindowController.shared.show(appState: appState, modelContainer: container)
                }
            }

            Section("Updates") {
                updateStatusRow

                updateDetailRow

                Toggle(isOn: $automaticallyCheckForUpdates) {
                    Text("Automatically check for updates")
                    Text("Checks GitHub Releases once a day at launch. Leave off to stay completely offline.")
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

    // MARK: - Inline Update UI

    private var updateStatusRow: some View {
        LabeledContent {
            updateActionControl
        } label: {
            updateStatusLabel
        }
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        switch updater.state {
        case .idle:
            Text("Software Update")
            Text("Checks GitHub Releases and verifies SHA-256 before installing.")

        case .checking:
            Text("Checking for Updates…")
            Text("Contacting GitHub Releases…")

        case .upToDate(let currentVersion, _):
            Label("You’re up to date!", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Popback \(currentVersion) is currently the newest version available.")

        case .available(let release):
            Text("Popback \(release.version.description) is available")
            Text("You currently have Popback \(updater.currentVersionString).")

        case .downloading(let release, let written, let total):
            Text("Downloading Popback \(release.version.description)…")
            Text(downloadProgressSubtitle(written: written, total: total))

        case .verifying(let release):
            Text("Verifying Popback \(release.version.description)…")
            Text("Checking SHA-256 integrity…")

        case .installing(let release):
            Text("Installing Popback \(release.version.description)…")
            Text("Popback will quit and reopen automatically.")

        case .readyToOpenDMG(let release, _):
            Label("Popback \(release.version.description) is ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("The verified disk image has been saved to Downloads and opened.")

        case .failed(let message, _):
            Label("Update Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
        }
    }

    @ViewBuilder
    private var updateActionControl: some View {
        switch updater.state {
        case .idle, .upToDate:
            Button("Check for Updates…") {
                updater.checkForUpdates(userInitiated: true)
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel") {
                    updater.cancelActiveTask()
                }
            }

        case .available(let release):
            if release.dmgAsset != nil {
                Button(
                    updater.installEligibility == .eligible
                        ? String(localized: "Install and Relaunch")
                        : String(localized: "Download and Open DMG")
                ) {
                    updater.startInstall(for: release)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Open Release Page…") {
                    updater.openReleasesPage(for: release)
                }
                .buttonStyle(.borderedProminent)
            }

        case .downloading, .verifying:
            Button("Cancel") {
                updater.cancelActiveTask()
            }

        case .installing:
            ProgressView()
                .controlSize(.small)

        case .readyToOpenDMG(_, let dmgURL):
            Button("Open DMG") {
                NSWorkspace.shared.open(dmgURL)
            }
            .buttonStyle(.borderedProminent)

        case .failed(_, let release):
            Button("Try Again") {
                if let release {
                    updater.startInstall(for: release)
                } else {
                    updater.checkForUpdates(userInitiated: true)
                }
            }
        }
    }

    @ViewBuilder
    private var updateDetailRow: some View {
        switch updater.state {
        case .downloading(_, let written, let total):
            if total > 0 {
                ProgressView(value: Double(min(written, total)), total: Double(total))
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

        case .verifying, .installing:
            ProgressView()
                .progressViewStyle(.linear)

        case .available(let release):
            VStack(alignment: .leading, spacing: 10) {
                Text("Release Notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    releaseNotesView(for: release)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 96, maxHeight: 170)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )

                if let note = eligibilityFootnote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Skip This Version") {
                        updater.skipVersion(release.version)
                    }
                    .controlSize(.small)

                    Spacer()

                    Button("Check for Updates…") {
                        updater.checkForUpdates(userInitiated: true)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)

        case .readyToOpenDMG(_, let dmgURL):
            HStack {
                Label(dmgURL.path, systemImage: "externaldrive.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([dmgURL])
                }
                .controlSize(.small)
            }

        case .idle, .checking, .upToDate, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func releaseNotesView(for release: UpdateReleaseInfo) -> some View {
        if release.releaseNotes.isEmpty {
            Text("No release notes provided.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let attributed = try? AttributedString(
            markdown: release.releaseNotes,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.callout)
                .textSelection(.enabled)
        } else {
            Text(verbatim: release.releaseNotes)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func downloadProgressSubtitle(written: Int64, total: Int64) -> String {
        let writtenText = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
        if total > 0 {
            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return String(localized: "\(writtenText) of \(totalText)")
        }
        return writtenText
    }

    private var eligibilityFootnote: String? {
        switch updater.installEligibility {
        case .eligible:
            if DirectPaste.isEnabled {
                return String(localized: "After updating, macOS may ask to re-enable Accessibility permission for Direct Paste.")
            }
            return nil
        case .developmentBuild:
            return String(localized: "This is a development or local build. Popback will download and open the verified DMG instead of replacing this app.")
        case .readOnlyLocation:
            return String(localized: "Popback isn’t in a writable Applications folder. The verified DMG will be downloaded and opened for manual installation.")
        }
    }
}

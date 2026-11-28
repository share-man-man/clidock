// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Resets dismissible prompts, onboarding status, saved Clip Queue window
/// geometry, and temporary cache files without touching clipboard history,
/// pinboards, excluded apps, or user preferences.
enum LocalStateReset {
    /// UserDefaults key tracking whether the first-run welcome tour finished.
    nonisolated static let onboardingCompletedKey = "hasCompletedOnboarding"

    /// Local state keys cleared by Settings > About > Reset Prompts & Cache.
    nonisolated static let userDefaultsKeys: [String] = [
        onboardingCompletedKey,
        ClipQueuePlacement.defaultsKey,
        ClipQueueWindowSize.defaultsKey,
        AppUpdateDefaults.lastCheckDateKey,
        AppUpdateDefaults.skippedVersionKey,
    ]

    /// Clears prompt flags, local window/onboarding defaults, and temporary files.
    static func reset(
        guide: inout DirectPastePermissionGuide,
        defaults: UserDefaults = .standard,
        tempDirectory: URL? = nil
    ) {
        guide.reset()
        for key in userDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
        if let tempDirectory {
            removeTempFiles(in: tempDirectory)
        }
    }

    /// Removes temporary files generated for image pastes and drags.
    static func removeTempFiles(in directory: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }
}

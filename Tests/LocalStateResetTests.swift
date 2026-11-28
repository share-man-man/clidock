// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class LocalStateResetTests: XCTestCase {
    func testResetClearsPromptsLocalDefaultsAndTempFilesWithoutTouchingPreferences() throws {
        let suiteName = "io.github.share-man-man.popback.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopbackResetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempFile = tempDir.appendingPathComponent("sample.png")
        try Data("png".utf8).write(to: tempFile)

        // Seed local state that should be cleared.
        var guide = DirectPastePermissionGuide()
        guide.dismissPanelBanner()
        XCTAssertTrue(guide.isBannerDismissed)
        XCTAssertTrue(guide.hasPromptedForRevocation)

        defaults.set(true, forKey: LocalStateReset.onboardingCompletedKey)
        defaults.set(Date(), forKey: AppUpdateDefaults.lastCheckDateKey)
        defaults.set("0.2.0", forKey: AppUpdateDefaults.skippedVersionKey)
        ClipQueuePlacement(fromLeft: true, horizontalInset: 20, topInset: 30).save(to: defaults)
        ClipQueueWindowSize.save(CGSize(width: 340, height: 380), to: defaults)

        // Seed user preferences that must remain intact.
        defaults.set(true, forKey: "pasteIntoActiveApp")
        defaults.set("Dark", forKey: "appTheme")
        defaults.set(500, forKey: "historyLimit")
        defaults.set(true, forKey: AppUpdateDefaults.autoCheckKey)

        LocalStateReset.reset(guide: &guide, defaults: defaults, tempDirectory: tempDir)

        // Prompt flags reset and re-arm guidance.
        XCTAssertFalse(guide.isBannerDismissed)
        XCTAssertFalse(guide.hasPromptedForRevocation)
        XCTAssertTrue(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))
        XCTAssertTrue(guide.consumePastePrompt(isEnabled: true, hasPermission: false))

        // Local ephemeral defaults removed.
        XCTAssertNil(defaults.object(forKey: LocalStateReset.onboardingCompletedKey))
        XCTAssertNil(defaults.object(forKey: AppUpdateDefaults.lastCheckDateKey))
        XCTAssertNil(defaults.object(forKey: AppUpdateDefaults.skippedVersionKey))
        XCTAssertNil(ClipQueuePlacement.load(from: defaults))
        XCTAssertNil(ClipQueueWindowSize.load(minimum: CGSize(width: 240, height: 140), from: defaults))

        // Temp files removed while leaving directory intact.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))

        // User preferences untouched.
        XCTAssertTrue(defaults.bool(forKey: "pasteIntoActiveApp"))
        XCTAssertEqual(defaults.string(forKey: "appTheme"), "Dark")
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), 500)
        XCTAssertTrue(defaults.bool(forKey: AppUpdateDefaults.autoCheckKey))
    }
}

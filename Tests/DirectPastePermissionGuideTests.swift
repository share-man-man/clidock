// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class DirectPastePermissionGuideTests: XCTestCase {
    func testNoGuidanceWhenDisabledOrGranted() {
        var guide = DirectPastePermissionGuide()

        XCTAssertFalse(guide.needsAttention(isEnabled: false, hasPermission: false))
        XCTAssertFalse(guide.shouldShowPanelBanner(isEnabled: false, hasPermission: false))
        XCTAssertFalse(guide.consumePastePrompt(isEnabled: false, hasPermission: false))

        XCTAssertFalse(guide.needsAttention(isEnabled: true, hasPermission: true))
        XCTAssertFalse(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: true))
        XCTAssertFalse(guide.consumePastePrompt(isEnabled: true, hasPermission: true))
    }

    func testRevocationShowsBannerAndPromptsOnceOnPaste() {
        var guide = DirectPastePermissionGuide()

        XCTAssertTrue(guide.needsAttention(isEnabled: true, hasPermission: false))
        XCTAssertTrue(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))

        // First fallback paste prompts; subsequent pastes do not nag.
        XCTAssertTrue(guide.consumePastePrompt(isEnabled: true, hasPermission: false))
        XCTAssertFalse(guide.consumePastePrompt(isEnabled: true, hasPermission: false))

        // Banner stays available until dismissed or resolved.
        XCTAssertTrue(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))
    }

    func testDismissingBannerAlsoSuppressesPasteAlertForCurrentRevocation() {
        var guide = DirectPastePermissionGuide()

        guide.dismissPanelBanner()

        XCTAssertTrue(guide.needsAttention(isEnabled: true, hasPermission: false))
        XCTAssertFalse(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))
        XCTAssertFalse(guide.consumePastePrompt(isEnabled: true, hasPermission: false))
    }

    func testRestoringPermissionResetsGuidanceForFutureRevocation() {
        var guide = DirectPastePermissionGuide()

        guide.dismissPanelBanner()
        XCTAssertFalse(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))

        // Permission restored in System Settings.
        guide.sync(isEnabled: true, hasPermission: true)
        XCTAssertFalse(guide.needsAttention(isEnabled: true, hasPermission: true))

        // Revoked again later: both banner and one-time alert re-arm.
        XCTAssertTrue(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))
        XCTAssertTrue(guide.consumePastePrompt(isEnabled: true, hasPermission: false))
    }

    func testDisablingAndReenablingDirectPasteResetsGuidance() {
        var guide = DirectPastePermissionGuide()

        XCTAssertTrue(guide.consumePastePrompt(isEnabled: true, hasPermission: false))
        XCTAssertFalse(guide.consumePastePrompt(isEnabled: true, hasPermission: false))

        guide.sync(isEnabled: false, hasPermission: false)

        XCTAssertTrue(guide.shouldShowPanelBanner(isEnabled: true, hasPermission: false))
        XCTAssertTrue(guide.consumePastePrompt(isEnabled: true, hasPermission: false))
    }
}

// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class URLCommandTests: XCTestCase {
    /// Unhosted tests have no Popback Info.plist, so pass the scheme it declares.
    private func command(_ string: String) -> URLCommand? {
        URL(string: string).flatMap { URLCommand(url: $0, schemes: ["popback"]) }
    }

    func testKnownCommands() {
        XCTAssertEqual(command("popback://open"), .open)
        XCTAssertEqual(command("popback://toggle"), .toggle)
        XCTAssertEqual(command("popback://queue"), .queue)
    }

    func testCaseAndFormVariants() {
        XCTAssertEqual(command("POPBACK://Open"), .open)
        XCTAssertEqual(command("popback:open"), .open)
        XCTAssertEqual(command("popback:///toggle"), .toggle)
    }

    func testUnknownOrForeignLinksAreIgnored() {
        XCTAssertNil(command("popback://delete-everything"))
        XCTAssertNil(command("popback://"))
        XCTAssertNil(command("https://open"))
    }
}

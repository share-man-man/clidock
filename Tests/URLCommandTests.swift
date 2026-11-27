// Modified for Clidock on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class URLCommandTests: XCTestCase {
    /// Unhosted tests have no Clidock Info.plist, so pass the scheme it declares.
    private func command(_ string: String) -> URLCommand? {
        URL(string: string).flatMap { URLCommand(url: $0, schemes: ["clidock"]) }
    }

    func testKnownCommands() {
        XCTAssertEqual(command("clidock://open"), .open)
        XCTAssertEqual(command("clidock://toggle"), .toggle)
        XCTAssertEqual(command("clidock://queue"), .queue)
    }

    func testCaseAndFormVariants() {
        XCTAssertEqual(command("CLIDOCK://Open"), .open)
        XCTAssertEqual(command("clidock:open"), .open)
        XCTAssertEqual(command("clidock:///toggle"), .toggle)
    }

    func testUnknownOrForeignLinksAreIgnored() {
        XCTAssertNil(command("clidock://delete-everything"))
        XCTAssertNil(command("clidock://"))
        XCTAssertNil(command("https://open"))
    }
}

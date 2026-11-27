import SwiftUI
import XCTest

@MainActor
final class CardColorsTests: XCTestCase {
    func testColorsPersistByTypeAndCanBeResetIndependently() throws {
        /// Keep this test's choices separate from those of the running app.
        let suite = UUID().uuidString
        /// Reuse the same defaults domain to simulate reopening the app.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        /// No overrides have been chosen on a fresh installation.
        let palette = CardColors(defaults: defaults)
        XCTAssertTrue(palette.isAtDefaults)
        for (index, type) in ContentType.allCases.enumerated() {
            palette[type] = Color.Resolved(red: Float(index) / Float(ContentType.allCases.count), green: 0, blue: 1)
        }
        /// All choices are available to a new instance before any view opens.
        let reopened = CardColors(defaults: defaults)
        for type in ContentType.allCases {
            /// Encoding sRGB and converting it back to linear RGB can round a channel.
            let saved = try XCTUnwrap(reopened[type])
            /// Compare the components at display precision.
            let chosen = try XCTUnwrap(palette[type])
            XCTAssertEqual(saved.red, chosen.red, accuracy: 1 / 255)
            XCTAssertEqual(saved.green, chosen.green, accuracy: 1 / 255)
            XCTAssertEqual(saved.blue, chosen.blue, accuracy: 1 / 255)
        }
        /// Resetting the text color must preserve the existing rich text override.
        let richTextColor = try XCTUnwrap(reopened[.richText])
        reopened[.plainText] = nil
        XCTAssertNil(CardColors(defaults: defaults)[.plainText])
        XCTAssertEqual(reopened.header(for: .plainText).background, DesignTokens.typeTint(for: .plainText))
        XCTAssertEqual(reopened[.richText], richTextColor)
        reopened.restoreDefaults()
        XCTAssertTrue(CardColors(defaults: defaults).isAtDefaults)
    }

    func testCopiedSwatchFallbackAndTextContrastForCustomColors() throws {
        /// An isolated palette for switching between the custom and copied color.
        let suite = UUID().uuidString
        /// The defaults domain is removed after checking the reset behavior.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        /// Color resolution here uses only fixed sRGB swatches.
        let environment = EnvironmentValues()
        /// White and black exercise both ends of the contrast range.
        let palette = CardColors(defaults: defaults)
        palette[.color] = Color.white.resolve(in: environment)
        XCTAssertEqual(palette.header(for: .color, itemColor: "#000000").foreground, .black)
        XCTAssertEqual(palette.header(for: .color, itemColor: "#000000").background.resolve(in: environment),
                       Color.white.resolve(in: environment))
        palette[.color] = nil
        XCTAssertEqual(palette.header(for: .color, itemColor: "#000000").background.resolve(in: environment),
                       Color.black.resolve(in: environment))
        XCTAssertEqual(palette.header(for: .color, itemColor: "#000000").foreground, .white)
        XCTAssertEqual(palette.header(for: .color, itemColor: "#FFFFFF").foreground, .black)
        palette[.plainText] = Color.black.resolve(in: environment)
        XCTAssertEqual(palette.header(for: .plainText).foreground, .white)
    }
}

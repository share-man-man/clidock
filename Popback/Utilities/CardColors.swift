import SwiftUI

/// Per-type header colors shared by the settings window, cards and Quick Look.
@MainActor
@Observable
final class CardColors {
    /// The dictionary uses stable content type identifiers across app languages.
    private static let defaultsKey = "cardHeaderColors"
    /// Local preferences for this installation.
    private let defaults: UserDefaults
    /// Only explicit choices are persisted so default system colors remain dynamic.
    private var overrides: [String: Color.Resolved] {
        didSet {
            if overrides.isEmpty {
                defaults.removeObject(forKey: Self.defaultsKey)
            } else if let data = try? JSONEncoder().encode(overrides) {
                defaults.set(data, forKey: Self.defaultsKey)
            }
        }
    }

    /// - Parameter defaults: Preferences used to restore and save the palette.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = defaults.data(forKey: Self.defaultsKey).flatMap {
            try? JSONDecoder().decode([String: Color.Resolved].self, from: $0)
        } ?? [:]
    }

    /// - Parameter type: The card type to customize. Assign nil to restore its default.
    subscript(type: ContentType) -> Color.Resolved? {
        get { overrides[type.rawValue] }
        set { overrides[type.rawValue] = newValue }
    }

    /// Whether every type uses its original color.
    var isAtDefaults: Bool { overrides.isEmpty }

    /// Restores all types, including matching a color clip's header to its swatch.
    func restoreDefaults() { overrides.removeAll() }

    /// - Parameters:
    ///   - type: The clip's stored content type.
    ///   - itemColor: The copied hex value when displaying a color clip.
    func header(for type: ContentType, itemColor: String? = nil) -> (background: Color, foreground: Color) {
        if let custom = self[type] { return contrastingHeader(custom) }
        if type == .color, let itemColor, let swatch = Color(hex: itemColor) {
            return contrastingHeader(swatch.resolve(in: EnvironmentValues()))
        }
        return (DesignTokens.typeTint(for: type), .white)
    }

    /// - Parameter color: An opaque background selected by the user or copied as a swatch.
    private func contrastingHeader(_ color: Color.Resolved) -> (background: Color, foreground: Color) {
        // Relative luminance of linear sRGB. At 0.179, black and white have equal contrast.
        let luminance = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return (Color(color), luminance > 0.179 ? .black : .white)
    }
}

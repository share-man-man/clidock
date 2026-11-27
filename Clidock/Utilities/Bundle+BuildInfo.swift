// Modified for Clidock on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import Foundation

extension Bundle {
    var appName: String {
        object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Clidock"
    }

    /// Badge drawn next to the menu bar icon for this build.
    var menuBadge: String? { menuLabel(forKey: "ClidockMenuBadge") }

    /// Build name shown above the native menu commands.
    var menuBanner: String? { menuLabel(forKey: "ClidockMenuBanner") }

    /// Reads the label supplied by the active build configuration.
    /// - Parameter key: Info.plist key whose empty value hides the label.
    private func menuLabel(forKey key: String) -> String? {
        // Release leaves both labels empty.
        guard let label = object(forInfoDictionaryKey: key) as? String, !label.isEmpty else { return nil }
        return label
    }

    var urlSchemes: Set<String> {
        /// URL types declared in Info.plist.
        let types = object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return Set(types.flatMap { ($0["CFBundleURLSchemes"] as? [String] ?? []).map { $0.lowercased() } })
    }
}

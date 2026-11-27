// Modified for Popback on 2026-11-27. SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// `popback://` links, so launchers such as Raycast or Alfred can open the
/// panel with their own shortcuts (#7).
///
///     popback://open     opens the history panel
///     popback://toggle   opens it, or closes it if it is open
///     popback://queue    starts or ends the Clip Queue
enum URLCommand: String, CaseIterable {
    case open
    case toggle
    case queue

    /// Reads a command from a link.
    /// - Parameters:
    ///   - url: the link that opened the app
    ///   - schemes: lowercased schemes to accept; defaults to the ones this build
    ///     registers in Info.plist (`popback`)
    init?(url: URL, schemes: Set<String> = Bundle.main.urlSchemes) {
        // macOS only hands the app links in schemes it registered, so this check is
        // defensive: it keeps parsing in line with the registered schemes.
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        // Accept both popback://open and popback:open.
        // URL.path is empty for popback:open on some macOS versions (CI), so
        // read the path from URLComponents.
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? ""
        let path = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let name = host.isEmpty ? path : host
        self.init(rawValue: name.lowercased())
    }
}

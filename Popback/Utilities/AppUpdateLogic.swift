// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import CryptoKit
import Foundation

// MARK: - UserDefaults Keys

enum AppUpdateDefaults {
    /// User preference (Settings > About): check GitHub Releases automatically once per day at launch.
    nonisolated static let autoCheckKey = "automaticallyCheckForUpdates"
    /// Ephemeral timestamp of the last successful update check.
    nonisolated static let lastCheckDateKey = "lastUpdateCheckDate"
    /// Dismissed version string when the user clicks "Skip This Version".
    nonisolated static let skippedVersionKey = "skippedUpdateVersion"
}

// MARK: - Semantic Version

/// Parsed version number supporting tags like "v0.2.0", "1.2", or "1.0.0-beta.1".
struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let components: [Int]
    let prerelease: String?

    init?(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        // Strip optional build metadata (+...)
        let withoutBuild = trimmed.split(separator: "+", maxSplits: 1).first.map(String.init) ?? trimmed
        let hyphenParts = withoutBuild.split(separator: "-", maxSplits: 1)
        let corePart = String(hyphenParts[0])
        let prereleasePart = hyphenParts.count > 1 ? String(hyphenParts[1]) : nil

        let rawNumbers = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard !rawNumbers.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(rawNumbers.count)
        for token in rawNumbers {
            guard !token.isEmpty, let value = Int(token), value >= 0 else { return nil }
            parsed.append(value)
        }

        self.components = parsed
        self.prerelease = (prereleasePart?.isEmpty == false) ? prereleasePart : nil
    }

    var description: String {
        let core = components.map(String.init).joined(separator: ".")
        if let prerelease {
            return "\(core)-\(prerelease)"
        }
        return core
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        compareCore(lhs.components, rhs.components) == .orderedSame && lhs.prerelease == rhs.prerelease
    }

    func hash(into hasher: inout Hasher) {
        var normalized = components
        while normalized.count > 1 && normalized.last == 0 {
            normalized.removeLast()
        }
        hasher.combine(normalized)
        hasher.combine(prerelease)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        switch compareCore(lhs.components, rhs.components) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil):
                return false
            case (.some, nil):
                // Prerelease is older than the corresponding stable release.
                return true
            case (nil, .some):
                return false
            case let (.some(a), .some(b)):
                return a.localizedStandardCompare(b) == .orderedAscending
            }
        }
    }

    private static func compareCore(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - GitHub Release Payload

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable, Equatable {
        let name: String
        let browserDownloadURL: URL
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
        case assets
    }
}

struct UpdateAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int64
}

struct UpdateReleaseInfo: Equatable, Sendable {
    let version: SemanticVersion
    let tagName: String
    let title: String
    let releaseNotes: String
    let htmlURL: URL
    let dmgAsset: UpdateAsset?
    let checksumAsset: UpdateAsset?
    let publishedAt: Date?

    /// Converts a GitHub release response into normalized update metadata.
    /// Returns `nil` when the release is a draft, has an unparseable version tag,
    /// or links to an untrusted host.
    static func from(release: GitHubRelease) -> UpdateReleaseInfo? {
        guard !release.draft,
              let version = SemanticVersion(release.tagName),
              UpdateHostValidator.isTrustedReleasePage(release.htmlURL) else {
            return nil
        }

        let trustedAssets = release.assets.filter {
            UpdateHostValidator.isTrustedDownloadURL($0.browserDownloadURL)
        }

        let dmg = selectDMGAsset(from: trustedAssets, version: version)
        let checksum = selectChecksumAsset(from: trustedAssets, version: version)

        let rawTitle = release.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "Popback \(version.description)" : rawTitle
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let publishedDate: Date? = release.publishedAt.flatMap { isoString in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: isoString) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: isoString)
        }

        return UpdateReleaseInfo(
            version: version,
            tagName: release.tagName,
            title: title,
            releaseNotes: notes,
            htmlURL: release.htmlURL,
            dmgAsset: dmg.map { UpdateAsset(name: $0.name, downloadURL: $0.browserDownloadURL, size: $0.size) },
            checksumAsset: checksum.map { UpdateAsset(name: $0.name, downloadURL: $0.browserDownloadURL, size: $0.size) },
            publishedAt: publishedDate
        )
    }

    private static func selectDMGAsset(
        from assets: [GitHubRelease.Asset],
        version: SemanticVersion
    ) -> GitHubRelease.Asset? {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        let expectedName = "Popback-\(version.description).dmg".lowercased()
        if let exact = dmgAssets.first(where: { $0.name.lowercased() == expectedName }) {
            return exact
        }
        // Prefer release DMGs over local-tagged images if multiple exist.
        if let nonLocal = dmgAssets.first(where: { !$0.name.lowercased().contains("-local") }) {
            return nonLocal
        }
        return dmgAssets.first
    }

    private static func selectChecksumAsset(
        from assets: [GitHubRelease.Asset],
        version: SemanticVersion
    ) -> GitHubRelease.Asset? {
        let shaAssets = assets.filter { $0.name.lowercased().hasSuffix(".sha256") }
        let expectedName = "Popback-\(version.description).sha256".lowercased()
        if let exact = shaAssets.first(where: { $0.name.lowercased() == expectedName }) {
            return exact
        }
        return shaAssets.first
    }
}

// MARK: - Host Validation

enum UpdateHostValidator {
    private static let trustedDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "github-releases.githubusercontent.com",
    ]

    static func isTrustedReleasePage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "github.com"
    }

    static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return trustedDownloadHosts.contains(host) || host.hasSuffix(".githubusercontent.com")
    }
}

// MARK: - SHA-256 Checksum

enum SHA256Checksum {
    /// Extracts the expected 64-char hex SHA-256 digest for `filename` from a
    /// `shasum -a 256` manifest (such as `Popback-0.2.0.sha256`).
    static func expectedHash(in manifest: String, forFile filename: String) -> String? {
        let targetName = (filename as NSString).lastPathComponent
        for rawLine in manifest.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // `shasum -a 256` emits `<64-hex>  <path>` or `<64-hex> *<path>`.
            guard let splitIndex = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
                continue
            }
            let hash = String(line[..<splitIndex]).lowercased()
            guard isValidHexDigest(hash) else { continue }

            var rest = line[splitIndex...].drop(while: { $0 == " " || $0 == "\t" })
            if rest.first == "*" {
                rest = rest.dropFirst()
            }
            let entryPath = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
            let entryName = (entryPath as NSString).lastPathComponent
            if entryName == targetName {
                return hash
            }
        }
        return nil
    }

    /// Computes the lowercase hex SHA-256 digest of a file using streaming reads.
    static func digest(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 256 * 1024
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(file url: URL, expectedHex: String) throws -> Bool {
        let normalized = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidHexDigest(normalized) else { return false }
        let actual = try digest(ofFile: url)
        return actual == normalized
    }

    private static func isValidHexDigest(_ string: String) -> Bool {
        string.count == 64 && string.allSatisfy {
            ("0"..."9").contains($0) || ("a"..."f").contains($0)
        }
    }
}

// MARK: - Install Eligibility

enum UpdateInstallEligibility: Equatable, Sendable {
    /// Release app bundle in a writable directory — can be replaced and relaunched in place.
    case eligible
    /// Debug (`PopbackDev`) or Local (`PopbackLocal`) build — should not be overwritten by Release `Popback.app`.
    case developmentBuild
    /// App is running from App Translocation, a mounted DMG, or a non-writable folder.
    case readOnlyLocation

    static func evaluate(
        bundleURL: URL,
        bundleIdentifier: String?,
        isParentDirectoryWritable: Bool
    ) -> UpdateInstallEligibility {
        guard bundleIdentifier == AppIdentity.releaseIdentifier else {
            return .developmentBuild
        }
        let path = bundleURL.standardizedFileURL.path
        guard bundleURL.pathExtension.lowercased() == "app" else {
            return .readOnlyLocation
        }
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            return .readOnlyLocation
        }
        guard isParentDirectoryWritable else {
            return .readOnlyLocation
        }
        return .eligible
    }
}

// MARK: - DMG Plist Parsing

enum DMGMountPlistParser {
    /// Extracts the first mounted volume path from `hdiutil attach -plist` XML output.
    static func mountPoint(from plistData: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            return nil
        }
        for entity in entities {
            if let path = entity["mount-point"] as? String, !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }
}

// MARK: - Atomic Replace Helper Script

enum UpdateHelperScript {
    /// POSIX shell script invoked as `/bin/sh <script> <oldPID> <stagedApp> <targetApp> <stagingDir>`.
    /// Waits for the old process to exit, atomically swaps the bundle with rollback on failure,
    /// relaunches the updated app, and cleans up the staging directory.
    static let contents = """
    #!/bin/sh
    set -eu

    OLD_PID="$1"
    STAGED_APP="$2"
    TARGET_APP="$3"
    STAGING_DIR="$4"
    BACKUP_APP="${TARGET_APP}.popback-update-backup"

    # Wait up to ~20 seconds for the running app to finish saving and exit.
    i=0
    while kill -0 "$OLD_PID" 2>/dev/null; do
        i=$((i + 1))
        if [ "$i" -ge 100 ]; then
            break
        fi
        sleep 0.2
    done

    rm -rf "$BACKUP_APP"

    if [ -e "$TARGET_APP" ]; then
        mv "$TARGET_APP" "$BACKUP_APP"
    fi

    if mv "$STAGED_APP" "$TARGET_APP"; then
        rm -rf "$BACKUP_APP"
        rm -rf "$STAGING_DIR"
        open -n "$TARGET_APP"
    else
        if [ -e "$BACKUP_APP" ] && [ ! -e "$TARGET_APP" ]; then
            mv "$BACKUP_APP" "$TARGET_APP"
        fi
        rm -rf "$STAGING_DIR"
        open -n "$TARGET_APP" 2>/dev/null || true
        exit 1
    fi
    """
}

import Foundation

/// Stable identifiers used by the local library, backups and pasteboard services.
enum AppIdentity {
    /// Bundle identifier of the original release and prefix of legacy backup files.
    private static let releaseIdentifier = "io.github.share-man-man.popback"
    /// Each installed build owns its own history, log subsystem and drag types.
    static let namespace = Bundle.main.bundleIdentifier ?? releaseIdentifier
    /// All configurations exchange the same backup format, including original 0.1.0 files.
    static let backupFormat = releaseIdentifier + ".backup"
    /// Canonical repository for feedback and manual update checks.
    private static let repository = URL(string: "https://github.com/share-man-man/popback")!
    /// Version history and downloadable DMGs.
    static let releasesURL = repository.appending(path: "releases")
    /// Public issue tracker.
    static let issuesURL = repository.appending(path: "issues")
}

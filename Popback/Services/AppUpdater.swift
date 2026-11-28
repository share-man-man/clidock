// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import os.log

enum AppUpdateError: LocalizedError, Sendable {
    case networkFailed(String)
    case rateLimited
    case noReleaseFound
    case missingDMGAsset
    case checksumMissingEntry
    case checksumMismatch
    case mountFailed
    case invalidAppBundle
    case codeSignatureInvalid
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .networkFailed(let detail):
            return String(localized: "Unable to connect to GitHub: \(detail)")
        case .rateLimited:
            return String(localized: "GitHub API rate limit exceeded. Please try again later or check Releases in your browser.")
        case .noReleaseFound:
            return String(localized: "No published release could be found on GitHub.")
        case .missingDMGAsset:
            return String(localized: "This release does not include a downloadable DMG installer.")
        case .checksumMissingEntry:
            return String(localized: "The release checksum file does not list the downloaded DMG.")
        case .checksumMismatch:
            return String(localized: "SHA-256 verification failed. The downloaded file may be corrupted or tampered with.")
        case .mountFailed:
            return String(localized: "Could not open the downloaded disk image.")
        case .invalidAppBundle:
            return String(localized: "The downloaded disk image does not contain a valid Popback app bundle.")
        case .codeSignatureInvalid:
            return String(localized: "Code signature verification failed for the downloaded app.")
        case .installFailed(let detail):
            return String(localized: "Could not complete installation: \(detail)")
        }
    }
}

/// Checks GitHub Releases for newer versions, verifies SHA-256 checksums,
/// and performs atomic in-place replacement with relaunch.
@MainActor
@Observable
final class AppUpdater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String, checkedAt: Date)
        case available(UpdateReleaseInfo)
        case downloading(release: UpdateReleaseInfo, bytesWritten: Int64, totalBytes: Int64)
        case verifying(release: UpdateReleaseInfo)
        case installing(release: UpdateReleaseInfo)
        case readyToOpenDMG(release: UpdateReleaseInfo, dmgURL: URL)
        case failed(message: String, release: UpdateReleaseInfo?)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .verifying, .installing:
                return true
            case .idle, .upToDate, .available, .readyToOpenDMG, .failed:
                return false
            }
        }
    }

    nonisolated static let autoCheckDefaultsKey = AppUpdateDefaults.autoCheckKey
    nonisolated static let lastCheckDateDefaultsKey = AppUpdateDefaults.lastCheckDateKey
    nonisolated static let skippedVersionDefaultsKey = AppUpdateDefaults.skippedVersionKey
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    private static let logger = Logger(popbackCategory: "AppUpdater")

    private(set) var state: State = .idle
    /// Remembered when a newer release is discovered so menu bar and Settings can badge it.
    private(set) var availableUpdate: UpdateReleaseInfo?

    @ObservationIgnored private var activeTask: Task<Void, Never>?

    var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var currentSemanticVersion: SemanticVersion {
        SemanticVersion(currentVersionString) ?? SemanticVersion("0.1.0")!
    }

    var installEligibility: UpdateInstallEligibility {
        let bundleURL = Bundle.main.bundleURL
        let parentDir = bundleURL.deletingLastPathComponent()
        let isWritable = FileManager.default.isWritableFile(atPath: parentDir.path)
        return UpdateInstallEligibility.evaluate(
            bundleURL: bundleURL,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            isParentDirectoryWritable: isWritable
        )
    }

    var lastCheckDate: Date? {
        UserDefaults.standard.object(forKey: Self.lastCheckDateDefaultsKey) as? Date
    }

    /// Runs a quiet background update check at most once per day when the user opted in.
    func performBackgroundCheckIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.autoCheckDefaultsKey) else { return }
        if let last = lastCheckDate, Date().timeIntervalSince(last) < Self.autoCheckInterval {
            return
        }
        checkForUpdates(userInitiated: false)
    }

    /// Checks GitHub Releases for a newer version.
    /// - Parameter userInitiated: When `true`, transitions through visible checking/result
    ///   states in Settings > About and ignores any previously skipped version.
    func checkForUpdates(userInitiated: Bool = true) {
        // Don't interrupt an active check, download, verification, or install.
        if state.isBusy {
            return
        }

        activeTask?.cancel()
        if userInitiated {
            state = .checking
        }

        let currentVersion = currentSemanticVersion
        let currentVersionText = currentVersionString
        let userAgent = "Popback/\(currentVersionText)"

        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let release = try await Self.fetchLatestRelease(userAgent: userAgent)
                guard !Task.isCancelled else { return }

                let now = Date()
                UserDefaults.standard.set(now, forKey: Self.lastCheckDateDefaultsKey)

                if release.version > currentVersion {
                    let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionDefaultsKey)
                    if userInitiated || skipped != release.version.description {
                        self.availableUpdate = release
                        self.state = .available(release)
                    } else if !userInitiated {
                        self.availableUpdate = nil
                        self.state = .idle
                    }
                } else {
                    self.availableUpdate = nil
                    if userInitiated {
                        self.state = .upToDate(currentVersion: currentVersionText, checkedAt: now)
                    } else {
                        self.state = .idle
                    }
                }
            } catch is CancellationError {
                if userInitiated {
                    self.state = .idle
                }
            } catch {
                Self.logger.error("Update check failed: \(error.localizedDescription)")
                if userInitiated {
                    self.state = .failed(message: error.localizedDescription, release: nil)
                }
            }
        }
    }

    /// Downloads the release DMG, verifies its SHA-256 checksum, and either replaces
    /// the current app bundle in place or opens the verified DMG for manual installation.
    func startInstall(for release: UpdateReleaseInfo) {
        guard !state.isBusy else { return }
        guard let dmgAsset = release.dmgAsset else {
            state = .failed(message: AppUpdateError.missingDMGAsset.localizedDescription, release: release)
            return
        }

        activeTask?.cancel()
        let eligibility = installEligibility
        let userAgent = "Popback/\(currentVersionString)"
        let targetBundleURL = Bundle.main.bundleURL

        state = .downloading(release: release, bytesWritten: 0, totalBytes: dmgAsset.size)

        activeTask = Task { [weak self] in
            guard let self else { return }
            let stagingDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("PopbackUpdate-\(UUID().uuidString)", isDirectory: true)
            var keepStagingDirForHelper = false
            defer {
                if !keepStagingDirForHelper {
                    try? FileManager.default.removeItem(at: stagingDir)
                }
            }

            do {
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                let downloadedDMG = stagingDir.appendingPathComponent(dmgAsset.name)

                try await FileDownloader.download(
                    from: dmgAsset.downloadURL,
                    to: downloadedDMG,
                    userAgent: userAgent
                ) { [weak self] written, expected in
                    let total = expected > 0 ? expected : dmgAsset.size
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if case .downloading = self.state {
                            self.state = .downloading(release: release, bytesWritten: written, totalBytes: total)
                        }
                    }
                }
                guard !Task.isCancelled else { return }

                // Verify SHA-256 when the release publishes a checksum manifest (always true for CI releases).
                self.state = .verifying(release: release)
                if let checksumAsset = release.checksumAsset {
                    let manifest = try await Self.fetchChecksumManifest(
                        from: checksumAsset.downloadURL,
                        userAgent: userAgent
                    )
                    guard !Task.isCancelled else { return }
                    guard let expectedHash = SHA256Checksum.expectedHash(in: manifest, forFile: dmgAsset.name) else {
                        throw AppUpdateError.checksumMissingEntry
                    }
                    let verified = try await Task.detached(priority: .userInitiated) {
                        try SHA256Checksum.verify(file: downloadedDMG, expectedHex: expectedHash)
                    }.value
                    guard verified else {
                        throw AppUpdateError.checksumMismatch
                    }
                }
                guard !Task.isCancelled else { return }

                if eligibility == .eligible {
                    self.state = .installing(release: release)
                    let stagedApp = try await Self.extractAndVerifyApp(
                        fromDMG: downloadedDMG,
                        into: stagingDir
                    )
                    guard !Task.isCancelled else { return }

                    try Self.launchReplacementHelper(
                        stagedApp: stagedApp,
                        targetApp: targetBundleURL,
                        stagingDir: stagingDir
                    )
                    keepStagingDirForHelper = true

                    // Terminating triggers PopbackApp's willTerminateNotification to save SwiftData.
                    NSApplication.shared.terminate(nil)
                } else {
                    let savedDMG = try Self.saveDMGForManualInstall(
                        from: downloadedDMG,
                        filename: dmgAsset.name
                    )
                    self.state = .readyToOpenDMG(release: release, dmgURL: savedDMG)
                    NSWorkspace.shared.open(savedDMG)
                }
            } catch is CancellationError {
                self.state = .available(release)
            } catch {
                Self.logger.error("Update install failed: \(error.localizedDescription)")
                self.state = .failed(message: error.localizedDescription, release: release)
            }
        }
    }

    func cancelActiveTask() {
        activeTask?.cancel()
        activeTask = nil
        switch state {
        case .downloading(let release, _, _), .verifying(let release):
            state = .available(release)
        case .checking:
            state = .idle
        default:
            break
        }
    }

    func skipVersion(_ version: SemanticVersion) {
        UserDefaults.standard.set(version.description, forKey: Self.skippedVersionDefaultsKey)
        if availableUpdate?.version == version {
            availableUpdate = nil
        }
        if case .available(let release) = state, release.version == version {
            state = .idle
        }
    }

    func openReleasesPage(for release: UpdateReleaseInfo? = nil) {
        NSWorkspace.shared.open(release?.htmlURL ?? AppIdentity.releasesURL)
    }

    // MARK: - Networking

    private static func fetchLatestRelease(userAgent: String) async throws -> UpdateReleaseInfo {
        var request = URLRequest(url: AppIdentity.latestReleaseAPIURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AppUpdateError.networkFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.noReleaseFound
        }
        switch http.statusCode {
        case 200:
            break
        case 404:
            throw AppUpdateError.noReleaseFound
        case 403, 429:
            throw AppUpdateError.rateLimited
        default:
            throw AppUpdateError.networkFailed("HTTP \(http.statusCode)")
        }

        let decoded: GitHubRelease
        do {
            decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw AppUpdateError.noReleaseFound
        }

        guard let info = UpdateReleaseInfo.from(release: decoded) else {
            throw AppUpdateError.noReleaseFound
        }
        return info
    }

    private static func fetchChecksumManifest(from url: URL, userAgent: String) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AppUpdateError.networkFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw AppUpdateError.checksumMissingEntry
        }
        return text
    }

    // MARK: - DMG Extraction & Verification

    /// Mounts the DMG read-only, validates the contained Popback.app bundle and code signature,
    /// copies it into `stagingDir`, and unmounts the DMG before returning.
    nonisolated private static func extractAndVerifyApp(
        fromDMG dmgURL: URL,
        into stagingDir: URL
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let attach = try runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: ["attach", "-nobrowse", "-readonly", "-plist", dmgURL.path]
            )
            guard attach.status == 0,
                  let mountPoint = DMGMountPlistParser.mountPoint(from: attach.stdout) else {
                throw AppUpdateError.mountFailed
            }

            defer {
                _ = try? runProcess(
                    executable: "/usr/bin/hdiutil",
                    arguments: ["detach", mountPoint.path, "-force"]
                )
            }

            let mountedApp = findAppBundle(in: mountPoint)
            guard let mountedApp else {
                throw AppUpdateError.invalidAppBundle
            }

            guard let bundle = Bundle(url: mountedApp),
                  bundle.bundleIdentifier == AppIdentity.releaseIdentifier else {
                throw AppUpdateError.invalidAppBundle
            }

            let verify = try runProcess(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", mountedApp.path]
            )
            guard verify.status == 0 else {
                throw AppUpdateError.codeSignatureInvalid
            }

            let stagedApp = stagingDir.appendingPathComponent(mountedApp.lastPathComponent)
            let copy = try runProcess(
                executable: "/usr/bin/ditto",
                arguments: [mountedApp.path, stagedApp.path]
            )
            guard copy.status == 0 else {
                throw AppUpdateError.installFailed("ditto exited with status \(copy.status)")
            }

            return stagedApp
        }.value
    }

    nonisolated private static func findAppBundle(in mountPoint: URL) -> URL? {
        let preferred = mountPoint.appendingPathComponent("Popback.app")
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil
        )) ?? []
        return items.first { $0.pathExtension.lowercased() == "app" }
    }

    private static func launchReplacementHelper(
        stagedApp: URL,
        targetApp: URL,
        stagingDir: URL
    ) throws {
        let scriptURL = stagingDir.appendingPathComponent("install-update.sh")
        try UpdateHelperScript.contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            targetApp.path,
            stagingDir.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw AppUpdateError.installFailed(error.localizedDescription)
        }
    }

    /// Saves a verified DMG into the user's Downloads folder when in-place replacement
    /// isn't eligible (e.g. dev/local build or read-only volume).
    private static func saveDMGForManualInstall(from downloadedURL: URL, filename: String) throws -> URL {
        let fm = FileManager.default
        let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        var destination = downloads.appendingPathComponent(filename)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            destination = downloads.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        try fm.copyItem(at: downloadedURL, to: destination)
        return destination
    }

    // MARK: - Subprocess Helper

    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: Data
    }

    nonisolated private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain stdout before waiting so large plist outputs never deadlock the pipe.
        let stdout = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessOutput(status: process.terminationStatus, stdout: stdout)
    }
}

// MARK: - Streaming File Downloader

/// Streams a remote file to disk with progress reporting and Task cancellation support.
private enum FileDownloader {
    static func download(
        from url: URL,
        to destination: URL,
        userAgent: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 120
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let delegate = Delegate(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: request)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.install(continuation: continuation, session: session)
                task.resume()
            }
        } onCancel: {
            task.cancel()
            session.invalidateAndCancel()
        }
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let destination: URL
        private let onProgress: @Sendable (Int64, Int64) -> Void
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        private var session: URLSession?
        private var didFinish = false

        init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func install(continuation: CheckedContinuation<Void, Error>, session: URLSession) {
            lock.lock()
            self.continuation = continuation
            self.session = session
            lock.unlock()
        }

        private func finish(with result: Result<Void, Error>) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            let cont = continuation
            let sess = session
            continuation = nil
            session = nil
            lock.unlock()

            sess?.finishTasksAndInvalidate()
            cont?.resume(with: result)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // Only follow HTTPS redirects (GitHub redirects release assets to githubusercontent.com).
            if request.url?.scheme?.lowercased() == "https" {
                completionHandler(request)
            } else {
                completionHandler(nil)
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            onProgress(totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                finish(with: .failure(AppUpdateError.networkFailed("HTTP \(http.statusCode)")))
                return
            }

            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.moveItem(at: location, to: destination)
                finish(with: .success(()))
            } catch {
                finish(with: .failure(AppUpdateError.installFailed(error.localizedDescription)))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                finish(with: .failure(CancellationError()))
            } else {
                finish(with: .failure(AppUpdateError.networkFailed(error.localizedDescription)))
            }
        }
    }
}

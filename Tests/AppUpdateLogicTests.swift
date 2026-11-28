// Modified for Popback on 2026-11-28. SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class AppUpdateLogicTests: XCTestCase {
    // MARK: - SemanticVersion

    func testSemanticVersionParsingAndComparison() throws {
        let v010 = try XCTUnwrap(SemanticVersion("0.1.0"))
        let v020 = try XCTUnwrap(SemanticVersion("v0.2.0"))
        let v0100 = try XCTUnwrap(SemanticVersion("V0.10.0"))
        let v10 = try XCTUnwrap(SemanticVersion("1.0"))
        let v100 = try XCTUnwrap(SemanticVersion("1.0.0"))
        let v100Beta = try XCTUnwrap(SemanticVersion("v1.0.0-beta.1"))
        let v100Beta2 = try XCTUnwrap(SemanticVersion("v1.0.0-beta.2"))

        XCTAssertLessThan(v010, v020)
        XCTAssertLessThan(v020, v0100)
        XCTAssertEqual(v10, v100)
        XCTAssertEqual(v10.hashValue, v100.hashValue)
        XCTAssertLessThan(v100Beta, v100Beta2)
        XCTAssertLessThan(v100Beta2, v100)
        XCTAssertEqual(v020.description, "0.2.0")
        XCTAssertEqual(v100Beta.description, "1.0.0-beta.1")

        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("v"))
        XCTAssertNil(SemanticVersion("release-2026"))
        XCTAssertNil(SemanticVersion("1..0"))
    }

    // MARK: - GitHub Release Decoding & Asset Selection

    func testUpdateReleaseInfoSelectsExpectedDMGAndChecksum() throws {
        let json = """
        {
          "tag_name": "v0.2.0",
          "name": "Popback 0.2.0",
          "body": "### What's New\\n- In-app updates",
          "html_url": "https://github.com/share-man-man/popback/releases/tag/v0.2.0",
          "draft": false,
          "prerelease": false,
          "published_at": "2026-11-28T12:00:00Z",
          "assets": [
            {
              "name": "Popback-0.2.0-source.tar.gz",
              "browser_download_url": "https://github.com/share-man-man/popback/releases/download/v0.2.0/Popback-0.2.0-source.tar.gz",
              "size": 100000
            },
            {
              "name": "Popback-0.2.0.dmg",
              "browser_download_url": "https://github.com/share-man-man/popback/releases/download/v0.2.0/Popback-0.2.0.dmg",
              "size": 5242880
            },
            {
              "name": "Popback-0.2.0.sha256",
              "browser_download_url": "https://github.com/share-man-man/popback/releases/download/v0.2.0/Popback-0.2.0.sha256",
              "size": 180
            }
          ]
        }
        """

        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        let info = try XCTUnwrap(UpdateReleaseInfo.from(release: release))

        XCTAssertEqual(info.version, SemanticVersion("0.2.0"))
        XCTAssertEqual(info.title, "Popback 0.2.0")
        XCTAssertEqual(info.dmgAsset?.name, "Popback-0.2.0.dmg")
        XCTAssertEqual(info.checksumAsset?.name, "Popback-0.2.0.sha256")
        XCTAssertNotNil(info.publishedAt)
    }

    func testUpdateReleaseInfoRejectsDraftAndUntrustedAssets() throws {
        let untrustedJSON = """
        {
          "tag_name": "v0.2.0",
          "name": "Popback 0.2.0",
          "body": "",
          "html_url": "https://github.com/share-man-man/popback/releases/tag/v0.2.0",
          "draft": false,
          "prerelease": false,
          "assets": [
            {
              "name": "Popback-0.2.0.dmg",
              "browser_download_url": "https://evil.example.com/Popback-0.2.0.dmg",
              "size": 123
            }
          ]
        }
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(untrustedJSON.utf8))
        let info = try XCTUnwrap(UpdateReleaseInfo.from(release: release))
        XCTAssertNil(info.dmgAsset)

        let draft = GitHubRelease(
            tagName: "v0.3.0",
            name: nil,
            body: nil,
            htmlURL: URL(string: "https://github.com/share-man-man/popback/releases/tag/v0.3.0")!,
            draft: true,
            prerelease: false,
            publishedAt: nil,
            assets: []
        )
        XCTAssertNil(UpdateReleaseInfo.from(release: draft))
    }

    // MARK: - SHA-256 Verification

    func testSHA256ManifestParsingAndFileVerification() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PopbackUpdaterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("Popback-0.2.0.dmg")
        try Data("popback-update-payload".utf8).write(to: fileURL)

        let actualHash = try SHA256Checksum.digest(ofFile: fileURL)
        let manifest = """
        0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  Popback-0.2.0-source.tar.gz
        \(actualHash.uppercased())  dist/Popback-0.2.0.dmg
        """

        let parsed = SHA256Checksum.expectedHash(in: manifest, forFile: "Popback-0.2.0.dmg")
        XCTAssertEqual(parsed, actualHash)
        XCTAssertTrue(try SHA256Checksum.verify(file: fileURL, expectedHex: actualHash))
        XCTAssertFalse(
            try SHA256Checksum.verify(
                file: fileURL,
                expectedHex: String(repeating: "0", count: 64)
            )
        )
        XCTAssertNil(SHA256Checksum.expectedHash(in: manifest, forFile: "Missing.dmg"))
    }

    // MARK: - Install Eligibility

    func testInstallEligibility() {
        let releaseApp = URL(fileURLWithPath: "/Applications/Popback.app")
        XCTAssertEqual(
            UpdateInstallEligibility.evaluate(
                bundleURL: releaseApp,
                bundleIdentifier: AppIdentity.releaseIdentifier,
                isParentDirectoryWritable: true
            ),
            .eligible
        )

        XCTAssertEqual(
            UpdateInstallEligibility.evaluate(
                bundleURL: URL(fileURLWithPath: "/Applications/PopbackLocal.app"),
                bundleIdentifier: AppIdentity.releaseIdentifier + ".local",
                isParentDirectoryWritable: true
            ),
            .developmentBuild
        )

        XCTAssertEqual(
            UpdateInstallEligibility.evaluate(
                bundleURL: URL(fileURLWithPath: "/Volumes/Popback/Popback.app"),
                bundleIdentifier: AppIdentity.releaseIdentifier,
                isParentDirectoryWritable: true
            ),
            .readOnlyLocation
        )

        XCTAssertEqual(
            UpdateInstallEligibility.evaluate(
                bundleURL: URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/ABC/d/Popback.app"),
                bundleIdentifier: AppIdentity.releaseIdentifier,
                isParentDirectoryWritable: true
            ),
            .readOnlyLocation
        )

        XCTAssertEqual(
            UpdateInstallEligibility.evaluate(
                bundleURL: releaseApp,
                bundleIdentifier: AppIdentity.releaseIdentifier,
                isParentDirectoryWritable: false
            ),
            .readOnlyLocation
        )
    }

    // MARK: - DMG Plist Parsing

    func testDMGMountPlistParserExtractsMountPoint() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>system-entities</key>
            <array>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk5</string>
                </dict>
                <dict>
                    <key>dev-entry</key>
                    <string>/dev/disk5s1</string>
                    <key>mount-point</key>
                    <string>/Volumes/Popback 1</string>
                </dict>
            </array>
        </dict>
        </plist>
        """

        let mountPoint = try XCTUnwrap(DMGMountPlistParser.mountPoint(from: Data(plist.utf8)))
        XCTAssertEqual(mountPoint.path, "/Volumes/Popback 1")
        XCTAssertNil(DMGMountPlistParser.mountPoint(from: Data("not a plist".utf8)))
    }
}

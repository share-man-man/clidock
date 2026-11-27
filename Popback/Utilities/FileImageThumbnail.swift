import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// Downsamples image files off the main actor, one at a time during rapid copies.
actor FileImageThumbnail {
    /// Shared decoder for newly captured and older file cards.
    private static let decoder = FileImageThumbnail()
    /// Enough pixels for a Retina card without retaining the original image.
    static let maxPixelSize = 640

    /// Stores only the preview; the clip's raw data remains the original file URL.
    /// - Parameters:
    ///   - item: A live single-file history record.
    ///   - url: The original file reference, possibly carrying a pasteboard sandbox grant.
    @MainActor
    static func storeIfNeeded(for item: ClipboardItem, from url: URL) async {
        guard item.modelContext != nil, !item.isDeleted, item.thumbnailData == nil,
              let data = await decoder.thumbnail(from: url) else { return }
        // The user may have deleted this record or another view may have filled it during decoding.
        guard !Task.isCancelled, let context = item.modelContext, !item.isDeleted, item.thumbnailData == nil else { return }
        item.thumbnailData = data
        try? context.save()
    }

    /// - Parameter url: File to read using the access granted by the original copy, if any.
    private func thumbnail(from url: URL) -> Data? {
        guard !Task.isCancelled, url.isFileURL else { return nil }
        /// Ordinary accessible files can be opened even when no security scope is required.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Skip folders, unavailable cloud files and unreadable references.
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey]),
              values.isRegularFile == true, values.ubiquitousItemDownloadingStatus != .notDownloaded,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source), UTType(identifier as String)?.conforms(to: .image) == true
        else { return nil }
        /// Decode a scaled, orientation-correct first frame rather than loading the full image into memory.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        /// Store a portable preview in the existing thumbnail field, preserving transparency.
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

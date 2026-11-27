import AppKit
import UniformTypeIdentifiers

/// The representations of a single pasteboard item, in preferred order.
typealias PasteboardRepresentations = [(NSPasteboard.PasteboardType, Data)]

/// One Finder copy, including the order of all its file references.
struct FileClip {
    /// Finder can publish both a file reference and a pixel representation in one copy.
    static let finderBundleID = "com.apple.finder"
    /// One URL per pasteboard item, even for files with identical names.
    let urls: [URL]

    /// Reads file references without opening the files or resolving aliases.
    /// - Parameter pasteboard: The clipboard supplied by the copying app.
    init?(pasteboard: NSPasteboard) {
        guard pasteboard.types?.contains(.fileURL) == true, let items = pasteboard.pasteboardItems else { return nil }
        /// A marker-only item is metadata; an unreadable advertised file still belongs to the selection.
        let files = items.filter { $0.types.contains(.fileURL) }
        /// Finder publishes each selected file in a separate item.
        let strings = files.compactMap { $0.string(forType: .fileURL) }
        guard strings.count == files.count else { return nil }
        self.init(strings: strings)
    }

    /// Reads both an older single URL and an ordered group from history or backup.
    /// - Parameter data: UTF-8 absolute URL strings separated by newlines.
    init?(data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        self.init(strings: string.components(separatedBy: "\n"))
    }

    /// Validates the complete group before using any of its references.
    /// - Parameter strings: One absolute file URL per element.
    private init?(strings: [String]) {
        /// Do not silently turn an unreadable group into a partial paste.
        let urls = strings.compactMap { URL(string: $0) }.filter(\.isFileURL)
        guard !urls.isEmpty, urls.count == strings.count else { return nil }
        self.urls = urls
    }

    /// URL encoding escapes newlines inside filenames. A single URL retains its original storage format.
    var rawData: Data { Data(urls.map(\.absoluteString).joined(separator: "\n").utf8) }

    /// Index every filename so any member can find the whole group.
    var names: String { urls.map(\.lastPathComponent).joined(separator: "\n") }

    /// Only a single image file gets the large file-card preview; groups keep their filename list.
    var singleImageURL: URL? {
        guard urls.count == 1, let url = urls.first,
              UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else { return nil }
        return url
    }

    /// Each file has its own URL and plain-text filename, as in a single-file paste.
    var pasteboardItems: [PasteboardRepresentations] {
        urls.map { url in
            [(.fileURL, Data(url.absoluteString.utf8)), (.string, Data(url.lastPathComponent.utf8))]
        }
    }
}

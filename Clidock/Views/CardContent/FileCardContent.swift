import SwiftUI
import AppKit

@MainActor
struct FileCardContent: View {
    /// File or Finder selection represented by this card.
    let item: ClipboardItem
    /// Highlights matching filenames while searching history.
    var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    @State private var cachedFileIcon: NSImage?

    private var fileName: String {
        item.textContent ?? "File"
    }

    var body: some View {
        /// A single URL uses the original icon layout. A Finder selection gets one row per visible file.
        let files = FileClip(data: item.rawData)
        if let files, files.urls.count > 1 {
            FileGroupCardContent(urls: files.urls, searchText: searchText)
        } else {
            singleFileContent
                .task(id: item.id) {
                    cachedFileIcon = files?.urls.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
                    // Existing Finder records can acquire a thumbnail the first time their card appears.
                    if item.sourceAppBundleId == FileClip.finderBundleID, let url = files?.singleImageURL {
                        await FileImageThumbnail.storeIfNeeded(for: item, from: url)
                    }
                }
        }
    }

    private var singleFileContent: some View {
        VStack(spacing: 6) {
            if item.thumbnailData != nil, let thumbnail = ThumbnailImageCache.image(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                Image(nsImage: cachedFileIcon ?? NSWorkspace.shared.icon(for: .data))
                    .resizable()
                    .frame(width: 32, height: 32)
            }

            Text(TextHighlighter.highlight(fileName, query: searchText))
                .font(.system(size: 11))
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.Body.textColor(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A compact Finder-style list that keeps the whole card available for one-click paste.
@MainActor
private struct FileGroupCardContent: View {
    /// Files in their original paste order.
    let urls: [URL]
    /// Current history query, used to reveal a matching file even in a large selection.
    let searchText: String

    /// Fixed row height keeps the last visible filename above the footer at every card size.
    private static let rowHeight: CGFloat = 30
    /// The Finder icon leaves room for a filename at the smallest card width.
    private static let iconSize: CGFloat = 20
    /// Separators start at the filename, aligned with the gap after its icon.
    private static let iconSpacing: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            /// Fill only complete rows; the parent supplies the card's insets.
            let rowCount = min(urls.count, max(1, Int(geometry.size.height / Self.rowHeight)))
            /// Keep visible rows in Finder order, including when a search match is revealed.
            let visible = visibleIndices(count: rowCount)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(visible, id: \.self) { index in
                    /// Use the index to preserve distinct files with the same name.
                    let url = urls[index]
                    HStack(spacing: Self.iconSpacing) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: Self.iconSize, height: Self.iconSize)
                            .accessibilityHidden(true)
                        Text(TextHighlighter.highlight(url.lastPathComponent, query: searchText))
                            .font(.system(size: DesignTokens.Body.fontSize))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if index == visible.last, rowCount < urls.count {
                            Text(verbatim: "+\((urls.count - rowCount).formatted())")
                                .font(DesignTokens.Footer.font.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .padding(.horizontal, 5)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .frame(height: Self.rowHeight)
                    .overlay(alignment: .bottom) {
                        if index != visible.last {
                            Divider().padding(.leading, Self.iconSize + Self.iconSpacing)
                        }
                    }
                }
            }
        }
    }

    /// - Parameter count: Number of complete rows that fit between header and footer.
    private func visibleIndices(count: Int) -> [Int] {
        /// Default to the beginning of the original selection.
        var indices = Array(urls.indices.prefix(count))
        // A card found by a later filename should show the user what matched.
        if !searchText.isEmpty,
           let match = urls.firstIndex(where: { $0.lastPathComponent.localizedCaseInsensitiveContains(searchText) }),
           match >= count {
            indices[count - 1] = match
        }
        return indices
    }
}

/// Both previews expose the full selection, including paths for identically named files.
@MainActor
struct FileClipPreview: View {
    /// The Finder selection represented by this card.
    let item: ClipboardItem

    var body: some View {
        if let files = FileClip(data: item.rawData) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(files.urls.indices, id: \.self) { index in
                        /// Keep Finder's original item order in the preview.
                        let url = files.urls[index]
                        HStack(spacing: 12) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: url.lastPathComponent)
                                    .font(.headline)
                                Text(verbatim: url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(verbatim: item.textContent ?? String(localized: "File"))
        }
    }
}

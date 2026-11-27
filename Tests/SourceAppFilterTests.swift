import XCTest

@MainActor
final class SourceAppFilterTests: XCTestCase {
    /// Creates a URL clip with the source metadata present on this particular device.
    /// - Parameters:
    ///   - name: Captured display name, when available.
    ///   - bundle: Stable identifier, which can be absent in imported records.
    private func clip(_ name: String?, _ bundle: String?) -> ClipboardItem {
        ClipboardItem(contentType: .url, rawData: Data(), textContent: "example",
                      sourceAppName: name, sourceAppBundleId: bundle, contentHash: "test")
    }

    func testSourceCombinesWithTextTypeAndDateAndClearsIndependently() {
        /// Record from the selected app that passes all four conditions.
        let match = clip("Browser", "test.browser")
        /// Identically named app from another publisher.
        let other = clip("Browser", "test.other")
        /// Outside today's date filter.
        let old = clip("Browser", "test.browser")
        old.copiedAt = .distantPast
        /// A matching source and text with the wrong content type.
        let wrongType = clip("Browser", "test.browser")
        wrongType.contentType = .plainText
        /// A matching source and type with different text.
        let wrongText = clip("Browser", "test.browser")
        wrongText.textContent = "different"
        /// Each filter independently excludes one candidate.
        let items = [match, other, old, wrongType, wrongText]
        /// Same filter model used by the panel and its keyboard navigation.
        let state = SearchState()
        state.sourceApp = .bundle("test.browser")
        state.dateFilter = .today
        state.selectedContentTypes = [.url]
        state.debouncedSearchText = "EXAMPLE"
        XCTAssertEqual(state.filteredItems(from: items).map(\.id), [match.id])
        state.sourceApp = nil
        XCTAssertEqual(state.filteredItems(from: items).map(\.id), [match.id, other.id])
        state.sourceApp = .unknown
        state.clearFilters()
        XCTAssertFalse(state.hasFilters)
        XCTAssertEqual(state.debouncedSearchText, "EXAMPLE")
        state.sourceApp = .unknown
        state.reset()
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.filteredItems(from: items).count, items.count)
    }

    func testMenuUsesBundleIdentityAndHandlesIncompleteSources() {
        /// Newer record has only an ID; an older record supplies its readable name.
        let items = [clip(nil, "test.app"), clip("App", "test.app"), clip("Legacy", nil), clip(nil, nil)]
        /// Menu choices use the same identities as the actual filtering.
        let options = SearchState.sourceOptions(from: items)
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.first { $0.source == .bundle("test.app") }?.title, "App")
        /// Legacy and unattributed clips are independently accessible.
        let state = SearchState()
        state.sourceApp = .name("Legacy")
        XCTAssertEqual(state.filteredItems(from: items).map(\.id), [items[2].id])
        state.sourceApp = .unknown
        XCTAssertEqual(state.filteredItems(from: items).map(\.id), [items[3].id])
        state.sourceApp = nil
        state.debouncedSearchText = "Legacy"
        XCTAssertTrue(state.filteredItems(from: items).isEmpty)
    }
}

import SwiftUI

@MainActor
@Observable
final class SearchState {
    var searchText: String = ""
    var debouncedSearchText: String = ""
    var selectedContentTypes: Set<ContentType> = []
    /// Nil includes every source, including records without attribution.
    var sourceApp: SourceApp?
    var dateFilter: DateFilter = .all
    var selectedIndex: Int? = nil

    private var debounceTask: Task<Void, Never>?

    /// Bundle identifiers survive renames. Imported clips can have only a name or no attribution.
    enum SourceApp: Hashable {
        case bundle(String)
        case name(String)
        case unknown

        /// - Parameter item: A stored clip with its original source metadata.
        init(_ item: ClipboardItem) {
            if let id = item.sourceAppBundleId, !id.isEmpty {
                self = .bundle(id)
            } else if let name = item.sourceAppName, !name.isEmpty {
                self = .name(name)
            } else {
                self = .unknown
            }
        }
    }

    /// Collects source choices from the entire history, independently of other active filters.
    /// - Parameter items: History ordered newest first, so the latest available app name wins.
    static func sourceOptions(from items: [ClipboardItem]) -> [(source: SourceApp, title: String)] {
        /// Fallback to the bundle ID if no clip has a readable name for this app.
        var titles: [SourceApp: String] = [:]
        for item in items {
            /// Identity used for both menu choices and matching.
            let source = SourceApp(item)
            if titles[source, default: ""].isEmpty {
                titles[source] = item.sourceAppName ?? ""
            }
        }
        return titles.map { source, name in
            if !name.isEmpty { return (source, name) }
            if case .bundle(let id) = source { return (source, id) }
            return (source, String(localized: "Unknown"))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    enum DateFilter: String, CaseIterable, Sendable {
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"

        /// Localized menu title. `rawValue` stays the stable English identifier.
        var displayName: String {
            switch self {
            case .all: String(localized: "All")
            case .today: String(localized: "Today")
            case .thisWeek: String(localized: "This Week")
            case .thisMonth: String(localized: "This Month")
            }
        }

        var startDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .all: return nil
            case .today: return calendar.startOfDay(for: Date())
            case .thisWeek:
                return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
            case .thisMonth:
                return calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))
            }
        }
    }

    var isActive: Bool {
        !searchText.isEmpty || hasFilters
    }

    /// Whether a type, source or date filter is narrowing the list.
    var hasFilters: Bool {
        !selectedContentTypes.isEmpty || sourceApp != nil || dateFilter != .all
    }

    func updateSearch(_ text: String) {
        // The field writes its text back when it loses focus. Same text, same
        // results: keep the selection (Tab out of the field relies on it).
        guard text != searchText else { return }
        searchText = text
        selectedIndex = nil
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            debouncedSearchText = text
        }
    }

    func reset() {
        searchText = ""
        debouncedSearchText = ""
        clearFilters()
        debounceTask?.cancel()
    }

    func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
        selectedIndex = nil
        debounceTask?.cancel()
    }

    /// Drops all filters, keeping the search text.
    func clearFilters() {
        selectedContentTypes = []
        sourceApp = nil
        dateFilter = .all
        selectedIndex = nil
    }

    func toggleContentType(_ type: ContentType) {
        if selectedContentTypes.contains(type) {
            selectedContentTypes.remove(type)
        } else {
            selectedContentTypes.insert(type)
        }
        selectedIndex = nil
    }

    func filteredItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        let startDate = dateFilter.startDate
        let contentTypes = selectedContentTypes
        let query = debouncedSearchText

        guard hasFilters || !query.isEmpty else {
            return items
        }

        return items.filter { item in
            if let sourceApp, SourceApp(item) != sourceApp {
                return false
            }
            if let startDate, item.copiedAt < startDate {
                return false
            }

            if !contentTypes.isEmpty, !contentTypes.contains(item.contentType) {
                return false
            }

            if !query.isEmpty {
                return item.matchesSearchQuery(query)
            }

            return true
        }
    }

    func moveSelection(by offset: Int, maxIndex: Int) {
        guard maxIndex >= 0 else { selectedIndex = nil; return }
        if let current = selectedIndex {
            selectedIndex = max(0, min(current + offset, maxIndex))
        } else {
            selectedIndex = 0
        }
    }

    func ensureSelection(itemCount: Int) {
        guard itemCount > 0 else {
            selectedIndex = nil
            return
        }

        if let current = selectedIndex {
            selectedIndex = max(0, min(current, itemCount - 1))
        } else {
            selectedIndex = 0
        }
    }
}

private extension ClipboardItem {
    func matchesSearchQuery(_ query: String) -> Bool {
        // Source app names are left out: the card doesn't show the app name,
        // so a clip matching only through it (a clip from "Aside" for "a")
        // looked like a wrong result.
        textContent?.localizedCaseInsensitiveContains(query) == true ||
        userTitle?.localizedCaseInsensitiveContains(query) == true
    }
}

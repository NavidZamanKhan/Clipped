import SwiftUI
import Combine

/// UI-observable state consumed by SwiftUI views.
///
/// This is a thin container for data that the views need to render.
/// It does not own any services — the `AppDelegate` owns the clipboard
/// monitor, SQLite database, and other long-lived resources. The
/// delegate updates these published properties whenever the underlying
/// data changes, and SwiftUI re-renders automatically.
@MainActor
final class AppState: ObservableObject {

    /// In-memory clipboard history, newest first. Mirrors the SQLite table.
    /// `HomeView` reads this directly via `@EnvironmentObject`.
    @Published var items: [ClipboardItem] = []

    /// The currently selected item's ID in the list. Drives native
    /// `List(selection:)` highlighting and keyboard navigation.
    @Published var selectedItemID: ClipboardItem.ID?

    /// The item ID that the ScrollViewReader should anchor to the top of the viewport.
    @Published var scrollTargetItemID: ClipboardItem.ID?

    /// Incremented whenever we want to force the view to scroll to the top item.
    @Published var scrollToTopTrigger: Int = 0

    /// The active search text entered by the user in the search field.
    @Published var searchText: String = ""

    /// Incremented when we want to programmatically focus the search text field in the UI.
    @Published var focusSearchTrigger: Int = 0

    /// The filtered clipboard history based on the active search text.
    var filteredItems: [ClipboardItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return items
        }
        return items.filter { item in
            switch item.contentType {
            case .text:
                return item.text.localizedCaseInsensitiveContains(trimmed)
            case .file:
                if let path = item.filePath {
                    let fileName = URL(fileURLWithPath: path).lastPathComponent
                    return fileName.localizedCaseInsensitiveContains(trimmed) || path.localizedCaseInsensitiveContains(trimmed)
                }
                return false
            case .image:
                return false
            }
        }
    }

    // MARK: - Sorting

    /// Sorts items so pinned entries remain on top (ordered chronologically by pinnedAt ASC so newly pinned items
    /// append naturally at the bottom of the pinned section), followed by unpinned history (ordered by copiedAt DESC).
    func sortItems() {
        items.sort { a, b in
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            if a.isPinned && b.isPinned {
                let aDate = a.pinnedAt ?? a.copiedAt
                let bDate = b.pinnedAt ?? b.copiedAt
                if aDate != bDate { return aDate < bDate }
                return a.id < b.id
            }
            if a.copiedAt != b.copiedAt {
                return a.copiedAt > b.copiedAt
            }
            return a.id > b.id
        }
    }

    // MARK: - Selection & Viewport Anchoring

    /// Selects the most recently copied clipboard item (whether pinned or unpinned) and anchors the viewport.
    ///
    /// When the panel appears:
    /// - Pointer / Selection: always lands directly on the latest copied item overall across history.
    /// - Viewport Anchor:
    ///   - If an item exists above the newest copy in the list (latestIndex > 0):
    ///     anchors the viewport to `items[latestIndex - 1]` at `.top` (Row 1), placing the selected
    ///     latest item consistently at Row 2 (whether pinned or unpinned)!
    ///   - If the newest copy is at index 0 (no items above it): anchors to itself at `.top` (Row 1).
    func selectNewest() {
        searchText = ""
        guard !items.isEmpty else {
            selectedItemID = nil
            scrollTargetItemID = nil
            scrollToTopTrigger += 1
            return
        }

        // Find the latest copied item overall across history, whether pinned or unpinned.
        let latestOverall = items.max(by: { a, b in
            if a.copiedAt != b.copiedAt {
                return a.copiedAt < b.copiedAt
            }
            return a.id < b.id
        })

        if let latestOverall,
           let latestIndex = items.firstIndex(where: { $0.id == latestOverall.id }) {
            selectedItemID = latestOverall.id

            // If an item exists above the newest copy in the list, anchor to it at .top (Row 1)
            // so the newest copy consistently appears at Row 2.
            if latestIndex > 0 {
                scrollTargetItemID = items[latestIndex - 1].id
            } else {
                scrollTargetItemID = latestOverall.id
            }
        }

        scrollToTopTrigger += 1
    }
}


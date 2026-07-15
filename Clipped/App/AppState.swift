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

    // MARK: - Selection

    /// Selects the newest clipboard item.
    ///
    /// Called by `WindowManager.showPanel()` immediately before the panel
    /// becomes visible, ensuring the correct item is highlighted on every
    /// show — deterministically and synchronously, without relying on
    /// SwiftUI's `onAppear` lifecycle callback.
    func selectNewest() {
        selectedItemID = items.first?.id
    }
}


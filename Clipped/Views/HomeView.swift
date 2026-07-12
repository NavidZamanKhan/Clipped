import SwiftUI

/// The main view displayed when the app launches.
///
/// In SwiftUI, a `View` is a struct that conforms to the `View` protocol.
/// This is conceptually similar to a StatelessWidget in Flutter — it
/// describes what the UI should look like. SwiftUI handles the rendering.
///
/// `some View` is an "opaque return type." You don't need to specify the
/// exact type; Swift infers it. Think of it like returning `Widget` in
/// Flutter, but the compiler knows the concrete type at compile time.
struct HomeView: View {

    /// `@State` is SwiftUI's equivalent of `setState()` in Flutter.
    /// When any `@State` value changes, SwiftUI automatically re-renders
    /// the parts of the view that depend on it.

    /// The in-memory list of clipboard history items, newest first.
    /// This stays synchronized with the database — every insert/trim
    /// updates both SQLite and this array, so the UI feels instant.
    @State private var items: [ClipboardItem] = []

    /// The SQLite-backed store. Created once when the view appears.
    /// It's optional because we create it in `.onAppear`, not in `init`.
    ///
    /// We use a `class` reference here so that the same store instance
    /// is used across re-renders. `@State` keeps its value stable
    /// across SwiftUI view re-renders — similar to how a Flutter
    /// `StatefulWidget` preserves its `State` object.
    @State private var store: ClipboardStore?

    /// The clipboard monitor. Also created once when the view appears.
    @State private var monitor: ClipboardMonitor?

    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("📋 Clipped")
                .font(.title)
            Text("Lightweight Clipboard Manager")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // Clipboard History section
            VStack(alignment: .leading, spacing: 8) {
                Text("Clipboard History")
                    .font(.headline)

                if items.isEmpty {
                    // Empty state — shown when there's no history at all.
                    Text("No clipboard history yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // `List` gives us a native macOS scrollable list with
                    // selection support and proper styling — similar to a
                    // Flutter `ListView.builder`.
                    //
                    // `ForEach` iterates over `items`. Because `ClipboardItem`
                    // conforms to `Identifiable`, SwiftUI uses each item's
                    // `id` to track which row is which (like `key` in Flutter).
                    List {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                // `.lineLimit(4)` prevents a huge copied code
                                // block from blowing out the layout. The text
                                // is truncated with "..." after 4 lines.
                                Text(item.text)
                                    .font(.body)
                                    .lineLimit(4)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)

                                // Show a relative timestamp like "2 minutes ago".
                                // `.relative` is a built-in SwiftUI date format
                                // that auto-updates. No manual formatting needed.
                                Text(item.copiedAt, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        // Sets the macOS window title in the title bar.
        .navigationTitle("Clipped")
        // `.onAppear` runs when the view is first shown on screen.
        // This is similar to `initState()` in a Flutter StatefulWidget.
        .onAppear {
            startUp()
        }
        // `.onDisappear` runs when the view is removed — like `dispose()`
        // in Flutter. We stop the timer to avoid leaking resources.
        .onDisappear {
            monitor?.stop()
        }
    }

    // MARK: - Private helpers

    /// Sets up the database, loads history, checks the current clipboard,
    /// and starts monitoring for future changes.
    private func startUp() {
        // 1. Open the database and load any saved history.
        let newStore = ClipboardStore()
        store = newStore
        items = newStore.loadAll()

        // 2. Check what's currently on the clipboard.
        //    macOS only retains the single most recent clipboard item,
        //    so we can't recover anything copied while Clipped was closed
        //    except this one.
        if let currentText = ClipboardService.currentText(), !currentText.isEmpty {
            // Only insert if it's different from the most recent saved item
            // (avoids duplicating on relaunch).
            let isDuplicate = items.first?.text == currentText
            if !isDuplicate {
                if let newItem = newStore.insert(text: currentText) {
                    items.insert(newItem, at: 0)
                    trimIfNeeded(store: newStore)
                }
            }
        }

        // 3. Start monitoring for future clipboard changes.
        let newMonitor = ClipboardMonitor()
        monitor = newMonitor

        newMonitor.start { newText in
            handleNewClip(text: newText)
        }
    }

    /// Called by the monitor each time new clipboard text is detected.
    private func handleNewClip(text: String) {
        guard let store else { return }

        // Skip consecutive duplicates.
        if items.first?.text == text { return }

        // Insert into SQLite and prepend to the in-memory list.
        if let newItem = store.insert(text: text) {
            items.insert(newItem, at: 0)
            trimIfNeeded(store: store)
        }
    }

    /// Ensures the history doesn't exceed 100 items.
    /// Trims both the SQLite table and the in-memory array.
    private func trimIfNeeded(store: ClipboardStore) {
        if items.count > 100 {
            store.trimToLimit()
            items = Array(items.prefix(100))
        }
    }
}

#Preview {
    HomeView()
}


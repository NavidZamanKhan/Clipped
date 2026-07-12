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
    /// Contains both text and image entries in interleaved order.
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
                                switch item.contentType {
                                case .text:
                                    // Text entry — same as before.
                                    // `.lineLimit(4)` prevents a huge copied code
                                    // block from blowing out the layout. The text
                                    // is truncated with "..." after 4 lines.
                                    Text(item.text)
                                        .font(.body)
                                        .lineLimit(4)
                                        .truncationMode(.tail)
                                        .textSelection(.enabled)

                                case .image:
                                    // Image entry — lazy thumbnail from file path.
                                    if let path = item.imagePath {
                                        ThumbnailView(path: path)
                                    } else {
                                        // Safety fallback if image_path is nil.
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

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
    ///
    /// Launch capture is mutually exclusive: text is checked first.
    /// If non-empty text is found, the image check is skipped entirely.
    private func startUp() {
        // 1. Open the database and load any saved history.
        let newStore = ClipboardStore()
        store = newStore
        items = newStore.loadAll()

        // 2. Check what's currently on the clipboard.
        //    macOS only retains the single most recent clipboard item,
        //    so we can't recover anything copied while Clipped was closed
        //    except this one.
        //
        //    Text first, else image — mutually exclusive.
        if let currentText = ClipboardService.currentText(), !currentText.isEmpty {
            // Only insert if it's different from the most recent saved text
            // (avoids duplicating on relaunch).
            let isDuplicate = items.first(where: { $0.contentType == .text })?.text == currentText
            if !isDuplicate {
                if let newItem = newStore.insert(text: currentText) {
                    items.insert(newItem, at: 0)
                    trimTextIfNeeded(store: newStore)
                }
            }
        } else if let currentImage = ClipboardService.currentImage() {
            // Save the image only if there's no text on the clipboard.
            handleNewImage(image: currentImage, store: newStore)
        }

        // 3. Start monitoring for future clipboard changes.
        let newMonitor = ClipboardMonitor()
        monitor = newMonitor

        newMonitor.start(
            onNewText: { newText in
                handleNewClip(text: newText)
            },
            onNewImage: { newImage in
                guard let store else { return }
                handleNewImage(image: newImage, store: store)
            }
        )
    }

    /// Called by the monitor each time new clipboard text is detected.
    private func handleNewClip(text: String) {
        guard let store else { return }

        // Skip consecutive duplicates.
        if items.first?.contentType == .text && items.first?.text == text { return }

        // Insert into SQLite and prepend to the in-memory list.
        if let newItem = store.insert(text: text) {
            items.insert(newItem, at: 0)
            trimTextIfNeeded(store: store)
        }
    }

    /// Saves a captured image to disk and inserts its metadata into SQLite.
    ///
    /// File-first, database-second: the PNG is written atomically before
    /// the database row is created. If the database insert fails, the
    /// newly created file is deleted to avoid orphans.
    private func handleNewImage(image: NSImage, store: ClipboardStore) {
        // 1. Save the PNG file atomically.
        guard let filePath = ImageStorage.saveImage(image) else { return }

        // 2. Insert metadata into SQLite.
        guard let newItem = store.insertImage(path: filePath) else {
            // Database insert failed — clean up the orphaned file.
            ImageStorage.deleteImage(at: filePath)
            return
        }

        // 3. Update the in-memory list.
        items.insert(newItem, at: 0)
        trimImagesIfNeeded(store: store)
    }

    /// Ensures the text history doesn't exceed 100 items.
    /// Trims both the SQLite table and the in-memory array.
    private func trimTextIfNeeded(store: ClipboardStore) {
        let textCount = items.filter { $0.contentType == .text }.count
        if textCount > 100 {
            store.trimText()
            // Remove overflow text items from the in-memory array.
            // Keep the newest 100 text items; remove older ones.
            var textSeen = 0
            items.removeAll { item in
                guard item.contentType == .text else { return false }
                textSeen += 1
                return textSeen > 100
            }
        }
    }

    /// Ensures the image history doesn't exceed 20 items.
    /// Trims the SQLite table, removes entries from the in-memory
    /// array, and deletes the orphaned PNG files.
    private func trimImagesIfNeeded(store: ClipboardStore) {
        let imageCount = items.filter { $0.contentType == .image }.count
        if imageCount > 20 {
            let deleted = store.trimImages()

            // Build a set of deleted IDs for fast lookup.
            let deletedIDs = Set(deleted.map { $0.id })

            // Remove those entries from the in-memory list.
            items.removeAll { deletedIDs.contains($0.id) }

            // Delete the orphaned PNG files.
            for entry in deleted {
                ImageStorage.deleteImage(at: entry.path)
            }
        }
    }
}

#Preview {
    HomeView()
}

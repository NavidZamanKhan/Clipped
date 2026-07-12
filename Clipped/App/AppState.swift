import SwiftUI
import AppKit
import Combine

/// The single source of truth for clipboard history, owned by `ClippedApp`.
///
/// Why this exists at the App level:
/// - The previous design lived inside `HomeView.onAppear/.onDisappear`,
///   which meant closing the Clipped window *stopped* monitoring.
/// - When Clipped becomes a menu-bar utility, the window can come and
///   go while the app keeps running. So the database handle, the
///   clipboard-monitor timer, and the in-memory items list all need
///   to outlive any view.
/// - Putting them in one `@MainActor` `ObservableObject` lets `HomeView`
///   subscribe declaratively, while a single instance keeps monitoring
///   alive even when no window is visible.
///
/// All work runs on the main actor (`@MainActor`). The monitor's timer
/// fires on the main run loop and we hop onto the main actor in the
/// callbacks, so SQLite calls and SwiftUI updates stay on the main thread.
@MainActor
final class AppState: ObservableObject {

    /// The SQLite-backed clipboard history. Opened once at startup;
    /// closed in `deinit` automatically.
    let store: ClipboardStore

    /// The clipboard-change poller. Started once in `start()` and left
    /// running for the lifetime of the app.
    let monitor: ClipboardMonitor

    /// In-memory history list, newest first. Mirrors the SQLite table.
    /// `HomeView` reads this directly via `@EnvironmentObject`.
    @Published private(set) var items: [ClipboardItem] = []

    /// Whether `start()` has already been called. Prevents double-start
    /// when the window is closed and reopened.
    private var hasStarted = false

    init() {
        self.store = ClipboardStore()
        self.monitor = ClipboardMonitor()
    }

    deinit {
        // The Timer attached to `monitor` must be invalidated when the
        // app is shutting down so it doesn't keep firing post-quit.
        // We touch the monitor through a non-isolated helper to avoid
        // requiring deinit to run on the main actor.
        monitor.invalidateFromAnyThread()
    }

    // MARK: - Lifecycle

    /// Opens the database, loads history, captures the current clipboard
    /// once, and starts polling for future changes. Idempotent.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // 1. Read any persisted history.
        items = store.loadAll()

        // 2. Capture whatever is currently on the clipboard exactly once.
        //    Text first; if non-empty text is found, skip image capture.
        if let currentText = ClipboardService.currentText(), !currentText.isEmpty {
            let isDuplicate = items.first(where: { $0.contentType == .text })?.text == currentText
            if !isDuplicate {
                if let newItem = store.insert(text: currentText) {
                    items.insert(newItem, at: 0)
                    trimTextIfNeeded()
                }
            }
        } else if let currentImage = ClipboardService.currentImage() {
            handleNewImage(currentImage)
        }

        // 3. Begin polling for future clipboard changes. The callbacks
        //    hop back onto the main actor before mutating `items`.
        monitor.start(
            onNewText: { [weak self] text in
                Task { @MainActor [weak self] in
                    self?.handleNewClip(text: text)
                }
            },
            onNewImage: { [weak self] image in
                Task { @MainActor [weak self] in
                    self?.handleNewImage(image)
                }
            }
        )
    }

    // MARK: - Insert / trim helpers

    /// Insert a newly observed clipboard text entry and trim overflow.
    private func handleNewClip(text: String) {
        // Skip consecutive duplicates (same string copied twice in a row).
        if items.first?.contentType == .text && items.first?.text == text { return }

        if let newItem = store.insert(text: text) {
            items.insert(newItem, at: 0)
            trimTextIfNeeded()
        }
    }

    /// Save the captured PNG, insert its metadata, and trim overflow.
    /// Mirrors the previous file-first / DB-second ordering in `HomeView`
    /// so that a failure to write the database row cleans up the orphan file.
    private func handleNewImage(_ image: NSImage) {
        guard let filePath = ImageStorage.saveImage(image) else { return }

        guard let newItem = store.insertImage(path: filePath) else {
            ImageStorage.deleteImage(at: filePath)
            return
        }

        items.insert(newItem, at: 0)
        trimImagesIfNeeded()
    }

    /// Drop oldest text items so that at most 100 remain.
    private func trimTextIfNeeded() {
        let textCount = items.filter { $0.contentType == .text }.count
        guard textCount > 100 else { return }

        store.trimText()

        // Remove overflow text items from the in-memory list.
        var textSeen = 0
        items.removeAll { item in
            guard item.contentType == .text else { return false }
            textSeen += 1
            return textSeen > 100
        }
    }

    /// Drop oldest image items and their PNG files so that at most 20 remain.
    private func trimImagesIfNeeded() {
        let imageCount = items.filter { $0.contentType == .image }.count
        guard imageCount > 20 else { return }

        let deleted = store.trimImages()
        let deletedIDs = Set(deleted.map { $0.id })
        items.removeAll { deletedIDs.contains($0.id) }

        for entry in deleted {
            ImageStorage.deleteImage(at: entry.path)
        }
    }
}

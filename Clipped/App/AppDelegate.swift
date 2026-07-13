import AppKit
import os

/// The application delegate and central service owner.
///
/// Owns all long-lived services: the SQLite database, clipboard monitor,
/// menu bar manager, and window manager. These are created at launch and
/// torn down at quit. The SwiftUI layer observes `appState` for UI
/// updates but never owns or controls services directly.
///
/// This separation keeps `AppState` thin (UI-observable state only)
/// and ensures services outlive any individual window.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "AppDelegate"
    )

    // MARK: - UI State

    /// UI-observable state consumed by SwiftUI views via `@EnvironmentObject`.
    /// Contains only published properties that the views need to render.
    let appState = AppState()

    // MARK: - Services

    /// The SQLite-backed clipboard history. Opened once during init;
    /// closed explicitly in `applicationWillTerminate`.
    private let store = ClipboardStore()

    /// The clipboard-change poller. Started in `applicationDidFinishLaunching`;
    /// stopped in `applicationWillTerminate`.
    private let monitor = ClipboardMonitor()

    /// Manages the menu bar icon and dropdown menu.
    private var menuBarManager: MenuBarManager?

    /// Manages window presentation.
    private let windowManager = WindowManager()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("Application launched")

        // 1. Load persisted history so the UI can display it immediately.
        appState.items = store.loadAll()

        // 2. Capture whatever is currently on the clipboard once.
        //    Text first; if non-empty text is found, skip image capture.
        captureCurrentClipboard()

        // 3. Begin polling for future clipboard changes. The callbacks
        //    hop onto the main actor before mutating state.
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

        // 4. Create the menu bar icon. "Show Clipped" is routed through
        //    WindowManager; the menu bar manager never touches windows.
        menuBarManager = MenuBarManager(onShowClipped: { [weak self] in
            self?.windowManager.showMainWindow()
        })

        Self.logger.info("All services started")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Returning false keeps the app alive when the user closes the
        // window. The app continues running in the menu bar, and the
        // clipboard monitor keeps polling. The user must explicitly
        // select "Quit" from the menu bar to terminate.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        store.close()
        Self.logger.info("Application terminated — all resources released")
    }

    // MARK: - Clipboard Handling

    /// Captures the current clipboard content once at launch.
    /// Text is checked first; if found, image capture is skipped.
    private func captureCurrentClipboard() {
        if let currentText = ClipboardService.currentText(), !currentText.isEmpty {
            let isDuplicate = appState.items
                .first(where: { $0.contentType == .text })?.text == currentText
            if !isDuplicate {
                if let newItem = store.insert(text: currentText) {
                    appState.items.insert(newItem, at: 0)
                    trimTextIfNeeded()
                }
            }
        } else if let currentImage = ClipboardService.currentImage() {
            handleNewImage(currentImage)
        }
    }

    /// Inserts a newly observed clipboard text entry and trims overflow.
    private func handleNewClip(text: String) {
        // Skip consecutive duplicates (same string copied twice in a row).
        if appState.items.first?.contentType == .text
            && appState.items.first?.text == text { return }

        if let newItem = store.insert(text: text) {
            appState.items.insert(newItem, at: 0)
            trimTextIfNeeded()
        }
    }

    /// Saves a captured PNG, inserts its metadata, and trims overflow.
    /// If the database insert fails, the orphan file is cleaned up.
    private func handleNewImage(_ image: NSImage) {
        guard let filePath = ImageStorage.saveImage(image) else { return }

        guard let newItem = store.insertImage(path: filePath) else {
            ImageStorage.deleteImage(at: filePath)
            return
        }

        appState.items.insert(newItem, at: 0)
        trimImagesIfNeeded()
    }

    /// Drops oldest text items so that at most 100 remain.
    private func trimTextIfNeeded() {
        let textCount = appState.items.filter { $0.contentType == .text }.count
        guard textCount > 100 else { return }

        store.trimText()

        // Remove overflow text items from the in-memory list.
        var textSeen = 0
        appState.items.removeAll { item in
            guard item.contentType == .text else { return false }
            textSeen += 1
            return textSeen > 100
        }
    }

    /// Drops oldest image items and their PNG files so that at most 20 remain.
    private func trimImagesIfNeeded() {
        let imageCount = appState.items.filter { $0.contentType == .image }.count
        guard imageCount > 20 else { return }

        let deleted = store.trimImages()
        let deletedIDs = Set(deleted.map { $0.id })
        appState.items.removeAll { deletedIDs.contains($0.id) }

        for entry in deleted {
            ImageStorage.deleteImage(at: entry.path)
        }
    }
}

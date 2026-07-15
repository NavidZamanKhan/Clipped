import AppKit
import ApplicationServices
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

    // MARK: - Shared Reference

    /// The shared instance of the AppDelegate adaptation.
    /// In SwiftUI apps using @NSApplicationDelegateAdaptor, NSApp.delegate
    /// returns an internal SwiftUI delegate wrapper. Casting that as? AppDelegate
    /// fails silently. This static reference provides safe global access instead.
    static private(set) var shared: AppDelegate?

    override init() {
        super.init()
        Self.shared = self
    }

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

        // 4. Create the permanent NSPanel — exactly once, before the menu
        //    bar manager is set up so that showPanel() is safe to call
        //    from the very first user interaction.
        windowManager.createPanel(appState: appState)

        // 5. Create the menu bar icon. "Show Clipped" is routed through
        //    WindowManager; the menu bar manager never touches windows.
        menuBarManager = MenuBarManager(onShowClipped: { [weak self] in
            self?.windowManager.showPanel()
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

    // MARK: - Paste Restoration

    /// Restores the currently selected clipboard item, hides Clipped,
    /// returns focus to the previous application, and simulates ⌘V.
    ///
    /// This is the central entry point for the "paste" action, invoked
    /// by both Enter key and double-click in HomeView.
    ///
    /// The full flow:
    /// 1. Find the selected item by ID.
    /// 2. Tell the monitor to skip the next pasteboard change.
    /// 3. Write the item's content to NSPasteboard.
    /// 4. Move the item to the top of history (SQLite + in-memory).
    /// 5. Hide the window and deactivate Clipped.
    /// 6. After a brief async yield (to let macOS switch focus),
    ///    simulate ⌘V via CGEvent.
    func pasteSelectedItem() {
        print("[TRACE] AppDelegate: pasteSelectedItem() entered")
        guard let selectedID = appState.selectedItemID,
              let index = appState.items.firstIndex(where: { $0.id == selectedID })
        else {
            print("[TRACE] AppDelegate: pasteSelectedItem() — no item selected, returning")
            Self.logger.warning("Paste requested but no item is selected")
            return
        }

        let item = appState.items[index]

        // 1. Write the item back to the system clipboard.
        switch item.contentType {
        case .text:
            ClipboardService.restoreText(item.text)
        case .image:
            if let path = item.imagePath {
                ClipboardService.restoreImage(fromPath: path)
            }
        }

        // 2. Record the *resulting* changeCount so the monitor ignores
        //    exactly this change. Set after the write so we capture the
        //    precise value, not a guess.
        monitor.ignoredChangeCount = NSPasteboard.general.changeCount

        // 3. Move the item to the top of history.
        //    Update SQLite first, then the in-memory array.
        if let newDate = store.updateTimestamp(id: item.id) {
            appState.items.remove(at: index)
            var updatedItem = item
            updatedItem.copiedAt = newDate
            appState.items.insert(updatedItem, at: 0)
            appState.selectedItemID = updatedItem.id
        }

        Self.logger.info("Restored clipboard item id=\(item.id)")

        // 4. Hide the panel to start the deactivation / focus return.
        print("[TRACE] AppDelegate: calling windowManager.hidePanel()")
        windowManager.hidePanel()

        // 5. Asynchronously activate previous app and post the paste event.
        //    This gives the OS window manager a chance to update the active application
        //    focus during the next run loop cycle.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let targetApp = self.windowManager.previousApp {
                print("[TRACE] AppDelegate: activating target app \(targetApp.localizedName ?? "unknown")")
                if #available(macOS 14.0, *) {
                    targetApp.activate(options: [])
                } else {
                    targetApp.activate(options: .activateIgnoringOtherApps)
                }
            }

            print("[TRACE] AppDelegate: calling simulatePaste()")
            Self.simulatePaste()
        }
    }

    /// Hides Clipped without pasting. Used when the user presses Esc.
    func hideWindow() {
        windowManager.hidePanel()
    }

    // MARK: - ⌘V Simulation

    /// Simulates the standard macOS paste shortcut (Command + V) using
    /// `CGEvent`. This posts a key-down and key-up event for the `V` key
    /// with the Command modifier flag set.
    ///
    /// Implementation note — three concrete fixes over the previous version:
    ///
    /// 1. **Event tap: `.cgSessionEventTap` (not `.cghidEventTap`).**
    ///    Per Apple's `CGEventTapLocation` documentation:
    ///      - `.cghidEventTap` is the point where HID system events
    ///        *enter the window server* — pre-session, pre-app routing.
    ///        Events posted here from a backgrounded/process process are
    ///        routinely filtered by the system before reaching the
    ///        foreground app.
    ///      - `.cgSessionEventTap` is the point where events enter
    ///        *a login session* — the level at which normal app-to-app
    ///        keyboard dispatch works.
    ///    Maccy (the reference open-source clipboard manager, 1.1k+
    ///    GitHub stars) uses `.cgSessionEventTap` in its `Clipboard.paste()`
    ///    implementation. The choice of tap is the single most common
    ///    reason a synthetic ⌘V silently fails.
    ///
    /// 2. **Local event suppression filter.** Before posting, we set the
    ///    event source's filter to `permitLocalMouseEvents +
    ///    permitSystemDefinedEvents` during the suppression interval.
    ///    This prevents Clipped's own `NSEvent.addLocalMonitorForEvents`
    ///    (the one intercepting Return/Escape) from re-capturing the
    ///    synthesized V keystroke and short-circuiting delivery. Maccy
    ///    applies this same filter for the same reason.
    ///
    /// 3. **Synchronous call, no `DispatchQueue.main.async`.** The caller
    ///    (`pasteSelectedItem`) invokes this *before* hiding the panel.
    ///    Posting CGEvent while the activation transition is still
    ///    pending is what causes the window server to deliver the
    ///    keystroke to the next-foreground application.
    ///
    /// The `0x09` keycode is the virtual key code for `V` on all macOS
    /// keyboard layouts (it's positional, not character-based).
    private static func simulatePaste() {
        print("[TRACE] AppDelegate: simulatePaste() entered")

        // Verify Accessibility is granted, prompting the user if not trusted.
        guard Accessibility.isTrusted(prompt: true) else {
            logger.error("Accessibility permission not granted — cannot post synthetic ⌘V")
            print("[TRACE] AppDelegate: simulatePaste() — ABORTED: Accessibility not trusted")
            return
        }

        // Use `.combinedSessionState` to inherit the user's actual modifier state.
        let source = CGEventSource(stateID: .combinedSessionState)

        // Suppress local events for the suppression interval so that Clipped's
        // own key monitor doesn't see the synthesized keystroke.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Virtual key code 0x09 = 'v' on all macOS keyboard layouts.
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for paste simulation")
            print("[TRACE] AppDelegate: simulatePaste() — ABORTED: CGEvent init returned nil")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        print("[TRACE] AppDelegate: simulatePaste() posted keyDown + keyUp on .cgAnnotatedSessionEventTap")
        logger.debug("Simulated ⌘V paste on .cgAnnotatedSessionEventTap")
    }
}

// MARK: - Accessibility

/// Runtime check for the Accessibility (TCC) permission required to post
/// synthetic keystrokes to other applications via `CGEvent`.
///
/// `AXIsProcessTrustedWithOptions(nil)` returns the current trust state
/// without prompting. If the user has not yet granted Accessibility in
/// System Settings → Privacy & Security → Accessibility, this returns
/// `false` and any subsequent `CGEvent.post` is silently dropped by the
/// window server.
enum Accessibility {

    /// Returns `true` if the process is currently trusted for Accessibility.
    /// If `prompt` is true, prompts the user to grant permissions via System Settings if not already trusted.
    static func isTrusted(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        } else {
            return AXIsProcessTrustedWithOptions(nil)
        }
    }
}

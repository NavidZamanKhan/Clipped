import AppKit
import os

/// Manages the menu bar status item and its dropdown menu.
///
/// Creates an `NSStatusItem` with a clipboard icon and a simple
/// menu containing "Show Clipped" and "Quit Clipped" actions.
///
/// Window restoration is delegated through the `onShowClipped`
/// callback — the menu bar manager never touches windows directly.
/// The `AppDelegate` wires this callback to `WindowManager`, keeping
/// responsibilities cleanly separated.
final class MenuBarManager: NSObject {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "MenuBarManager"
    )

    /// The system status item displayed in the menu bar.
    /// Retained here to keep the icon visible for the app's lifetime.
    private var statusItem: NSStatusItem?

    /// Called when the user selects "Show Clipped" from the dropdown.
    /// Routed through `AppDelegate` → `WindowManager`.
    private let onShowClipped: () -> Void

    /// Creates the menu bar manager and immediately installs the
    /// status item in the system menu bar.
    ///
    /// - Parameter onShowClipped: Callback invoked when the user
    ///   selects "Show Clipped". The caller is responsible for
    ///   routing this to the appropriate window manager.
    init(onShowClipped: @escaping () -> Void) {
        self.onShowClipped = onShowClipped
        super.init()
        setupStatusItem()
    }

    // MARK: - Private

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        statusItem?.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "Clipped"
        )

        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "Show Clipped",
            action: #selector(showClipped),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let testPasteItem = NSMenuItem(
            title: "Test Paste",
            action: #selector(testPasteClick),
            keyEquivalent: ""
        )
        testPasteItem.target = self
        menu.addItem(testPasteItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Clipped",
            action: #selector(quitClipped),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        Self.logger.debug("Menu bar status item created")
    }

    @objc private func showClipped() {
        onShowClipped()
    }

    @objc private func testPasteClick() {
        print("[TRACE] MenuBarManager: Test Paste clicked")
        AppDelegate.simulatePaste()
    }

    @objc private func quitClipped() {
        NSApp.terminate(nil)
    }
}

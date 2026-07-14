import AppKit
import os

/// Manages the presentation of application windows.
///
/// Provides a clean API for showing the main window from any
/// non-SwiftUI context (e.g., the menu bar manager). Uses AppKit's
/// `NSApp` to locate and present the window that SwiftUI's
/// `WindowGroup` scene created.
final class WindowManager {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "WindowManager"
    )

    /// Activates the application and brings the main window to the front.
    ///
    /// If the window was previously closed (ordered out by the user),
    /// this restores it. SwiftUI's `WindowGroup` keeps the underlying
    /// `NSWindow` alive after close, so `makeKeyAndOrderFront`
    /// re-presents it without creating a duplicate.
    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            Self.logger.debug("Main window restored")
        } else {
            Self.logger.warning("No main window found to restore")
        }
    }

    /// Hides the main window and deactivates Clipped, allowing the
    /// previously-focused application to regain focus.
    func hideMainWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.orderOut(nil)
            Self.logger.debug("Main window hidden")
        }
        NSApp.hide(nil)
    }
}

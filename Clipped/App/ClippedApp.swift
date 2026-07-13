import SwiftUI
import AppKit

/// The application entry point.
///
/// `@main` marks this struct as the app's launch point.
///
/// The `App` declares a single `WindowGroup` scene for the clipboard
/// history UI. All long-lived services (clipboard monitor, SQLite,
/// menu bar) are owned by `AppDelegate`, not by the SwiftUI layer.
///
/// The menu bar icon is managed by `MenuBarManager` (an AppKit
/// `NSStatusItem`), created in `AppDelegate.applicationDidFinishLaunching`.
/// This keeps window and menu bar management in the delegate layer
/// where they can be coordinated cleanly.
@main
struct ClippedApp: App {

    /// Bridges the SwiftUI lifecycle with `NSApplicationDelegate`.
    /// The delegate owns all long-lived services and coordinates
    /// application lifecycle events (launch, close, quit).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            HomeView()
                .environmentObject(appDelegate.appState)
        }
        // Sets the default window size when the app first launches.
        // The user can still resize freely after that.
        .defaultSize(width: 420, height: 600)
        .commands {
            // Prevent ⌘N from creating duplicate windows. Clipped
            // should only ever have one main window.
            CommandGroup(replacing: .newItem) {}

            // Replace the default Quit with an explicit ⌘Q handler
            // so the shortcut works when the window is focused.
            CommandGroup(replacing: .appTermination) {
                Button("Quit Clipped") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

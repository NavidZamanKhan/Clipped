import SwiftUI
import AppKit

/// The application entry point.
///
/// `@main` marks this struct as the app's launch point — similar to
/// `void main()` in Dart or `runApp()` in Flutter.
///
/// `App` is a protocol (like an interface/abstract class in Dart).
/// Conforming to it requires a `body` that returns one or more `Scene`s.
///
/// A `Scene` manages a window or group of windows. `WindowGroup` is the
/// standard scene type for document-based or single-window apps on macOS.
///
/// Clipped has two scenes:
///   - A `WindowGroup` for the actual history UI (may be closed).
///   - A `MenuBarExtra` that gives the user a permanent tray icon with
///     "Show Clipped" and "Quit Clipped" actions. As long as the process
///     is alive (i.e. the user has not Quit), clipboard monitoring
///     continues even with no window visible.
@main
struct ClippedApp: App {

    /// The single source of truth for the app — owned by `App`, not by
    /// any view, so it survives window close/reopen.
    ///
    /// `@StateObject` (rather than `@State`) is the SwiftUI-blessed way
    /// to own an `ObservableObject` from inside an `App`. It guarantees
    /// one instance per app launch and deinitializes when the app exits.
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            HomeView()
                .environmentObject(appState)
                // `task` runs once when the view first appears.
                // Safe even if the window is later closed and reopened:
                // `AppState.start()` is idempotent via the `hasStarted` guard.
                .task {
                    appState.start()
                }
        }
        // Sets the default window size when the app first launches.
        // The user can still resize freely after that.
        .defaultSize(width: 420, height: 600)

        // Always-on system tray icon. `.menu` style is a classic macOS
        // drop-down menu — simpler than a popover and matches the
        // expected look for menu-bar utilities.
        //
        // The menu content is itself a `View`, which is where SwiftUI's
        // `@Environment(\.openWindow)` action lives — that's why we
        // can't call it directly from the `App` body.
        MenuBarExtra {
            MenuBarContent()
        } label: {
            // A small clipboard glyph. SF Symbols renders crisply in
            // the menu bar; the system tints it automatically.
            Image(systemName: "clipboard")
        }
        .menuBarExtraStyle(.menu)

        // Add a real ⌘Q shortcut so users on a keyboard don't have to
        // chase the menu bar to quit. `.appTermination` is the standard
        // command group that hosts "Quit" in macOS apps.
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Clipped") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

/// The contents of the menu-bar dropdown.
///
/// Lives in its own `View` so we can access `@Environment(\.openWindow)`,
/// which is the SwiftUI-blessed way to ask the system to open a
/// `WindowGroup` window by id. Calling this from the `App` body
/// directly doesn't compile — the action is only injected into views.
private struct MenuBarContent: View {

    /// SwiftUI injects this in views, not in scenes. Asking the
    /// environment to `openWindow(id: "main")` brings the existing
    /// history window to the front (or creates one if it was closed
    /// and SwiftUI tore it down).
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Clipped") {
            // Activate first so the window comes forward even when
            // another app is frontmost; then ask SwiftUI to open it.
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Button("Quit Clipped") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

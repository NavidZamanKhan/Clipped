import SwiftUI
import AppKit

/// The application entry point.
///
/// `@main` marks this struct as the app's launch point.
///
/// # Window management
///
/// This App struct deliberately uses a `Settings` scene instead of a
/// `WindowGroup`. A `WindowGroup` would cause SwiftUI to create and
/// manage its own `NSWindow`, which conflicts with the permanent
/// `NSPanel` that `WindowManager` owns directly.
///
/// The `Settings` scene produces no visible window on launch
/// (it only activates via Preferences menu), giving AppKit full
/// authority over the application's window lifecycle.
///
/// # Service ownership
///
/// All long-lived services (clipboard monitor, SQLite, menu bar, panel)
/// are owned by `AppDelegate`, not by the SwiftUI scene layer. The
/// delegate creates and wires everything in `applicationDidFinishLaunching`.
@main
struct ClippedApp: App {

    /// Bridges the SwiftUI lifecycle with `NSApplicationDelegate`.
    /// The delegate owns all long-lived services and coordinates
    /// application lifecycle events (launch, close, quit).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A Settings scene with no content. This satisfies the SwiftUI
        // App protocol requirement of at least one scene, without
        // producing a window that would conflict with our NSPanel.
        Settings {
            EmptyView()
        }
    }
}

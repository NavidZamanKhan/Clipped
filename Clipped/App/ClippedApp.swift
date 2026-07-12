import SwiftUI

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
@main
struct ClippedApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        // Sets the default window size when the app first launches.
        // The user can still resize freely after that.
        .defaultSize(width: 420, height: 600)
    }
}

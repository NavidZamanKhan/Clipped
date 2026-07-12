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
    /// When this value changes, SwiftUI automatically re-renders the
    /// parts of the view that depend on it.
    ///
    /// We mark it `private` because this state belongs only to this view.
    /// The `?` means the value is optional — it can be `nil` (like
    /// `null` in Dart). `nil` here means "we haven't read the clipboard
    /// yet" or "the clipboard had no plain text."
    @State private var clipboardText: String?

    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("📋 Clipped")
                .font(.title)
            Text("Lightweight Clipboard Manager")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // Current Clipboard section
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Clipboard")
                    .font(.headline)

                if let text = clipboardText {
                    // `ScrollView` lets long clipboard text scroll rather
                    // than clipping or stretching the window — similar to
                    // wrapping a Flutter widget in a SingleChildScrollView.
                    //
                    // `.textSelection(.enabled)` lets the user select and
                    // copy the displayed text, which is disabled by default
                    // in SwiftUI on macOS.
                    ScrollView {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Clipboard is empty.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Footer note
            Text("Clipboard monitoring will be implemented in the next milestone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        // Sets the macOS window title in the title bar.
        .navigationTitle("Clipped")
        // `.onAppear` runs once when the view is first shown on screen.
        // This is similar to `initState()` in a Flutter StatefulWidget.
        // We read the clipboard here exactly once — no timers, no
        // polling, no live updates.
        .onAppear {
            clipboardText = ClipboardService.currentText()
        }
    }
}

#Preview {
    HomeView()
}

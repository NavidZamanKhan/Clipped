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
///
/// History is owned by `AppState` (injected from the `App`), so this
/// view is a thin, declarative presentation layer. The clipboard
/// monitor keeps running even when this view is not on screen.
struct HomeView: View {

    /// The shared application state. Provided via `.environmentObject(appState)`
    /// from `ClippedApp`. Reading `items` here is enough — SwiftUI will
    /// re-render whenever the published value changes.
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("📋 Clipped")
                .font(.title)
            Text("Lightweight Clipboard Manager")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            // Clipboard History section
            VStack(alignment: .leading, spacing: 8) {
                Text("Clipboard History")
                    .font(.headline)

                if appState.items.isEmpty {
                    // Empty state — shown when there's no history at all.
                    Text("No clipboard history yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // `List` gives us a native macOS scrollable list with
                    // selection support and proper styling — similar to a
                    // Flutter `ListView.builder`.
                    //
                    // `ForEach` iterates over `items`. Because `ClipboardItem`
                    // conforms to `Identifiable`, SwiftUI uses each item's
                    // `id` to track which row is which (like `key` in Flutter).
                    List {
                        ForEach(appState.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                switch item.contentType {
                                case .text:
                                    // Text entry — same as before.
                                    // `.lineLimit(4)` prevents a huge copied code
                                    // block from blowing out the layout. The text
                                    // is truncated with "..." after 4 lines.
                                    Text(item.text)
                                        .font(.body)
                                        .lineLimit(4)
                                        .truncationMode(.tail)
                                        .textSelection(.enabled)

                                case .image:
                                    // Image entry — lazy thumbnail from file path.
                                    if let path = item.imagePath {
                                        ThumbnailView(path: path)
                                    } else {
                                        // Safety fallback if image_path is nil.
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                // Show a relative timestamp like "2 minutes ago".
                                // `.relative` is a built-in SwiftUI date format
                                // that auto-updates. No manual formatting needed.
                                Text(item.copiedAt, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        // Sets the macOS window title in the title bar.
        .navigationTitle("Clipped")
        // No `onAppear` / `onDisappear` lifecycle hooks are needed here.
        // The clipboard monitor is owned by `AppDelegate` and runs
        // independently of any window. Closing the window does not
        // affect monitoring.
    }
}

#Preview {
    HomeView().environmentObject(AppState())
}

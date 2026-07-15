import SwiftUI

/// The main view displayed when the app launches.
///
/// Presents the clipboard history as a native macOS list with full
/// keyboard navigation. The newest item is auto-selected on appear.
///
/// Keyboard:
///   ↑ / ↓ — navigate items (handled natively by `List(selection:)`)
///   Enter  — restore selected item to clipboard and paste (⌘V)
///   Esc    — hide Clipped without pasting
///
/// Mouse:
///   Single click  — change selection
///   Double click   — restore and paste (same as Enter)
///   Scroll wheel   — scroll normally
struct HomeView: View {

    /// The shared application state. Provided via `.environmentObject(appState)`
    /// from `ClippedApp`. Contains the items array and the current selection.
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            // Header
            Text("Clipped")
                .font(.title)

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
                    // `List(selection:)` provides native macOS keyboard
                    // navigation: ↑/↓ arrow keys change selection,
                    // highlighted row tracks `selectedItemID`.
                    List(selection: $appState.selectedItemID) {
                        ForEach(appState.items) { item in
                            ClipboardRow(item: item)
                                .tag(item.id)
                                .onDoubleClick {
                                    appState.selectedItemID = item.id
                                    pasteSelectedItem()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .listRowBackground(
                                    appState.selectedItemID == item.id
                                        ? nil // nil delegates to standard selection highlight
                                        : Color.clear
                                )
                                .listRowSeparator(.visible)
                                .listRowSeparatorTint(Color.primary.opacity(0.1))
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: false))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        // Sets the macOS window title in the title bar.
        .navigationTitle("Clipped")
        // Keyboard handling (Return → paste, Escape → hide) is managed
        // by the AppKit local event monitor in WindowManager, not by
        // SwiftUI's .onKeyPress. See WindowManager.installKeyMonitor().
    }

    // MARK: - Actions

    /// Routes the paste action to `AppDelegate` via `NSApp.delegate`.
    ///
    /// HomeView doesn't own services — it reaches the delegate through
    /// `NSApp.delegate`, which is the standard AppKit pattern for
    /// accessing the app delegate from any context.
    private func pasteSelectedItem() {
        guard let delegate = AppDelegate.shared else { return }
        delegate.pasteSelectedItem()
    }

    /// Routes the hide action to `AppDelegate`.
    private func hideWindow() {
        guard let delegate = AppDelegate.shared else { return }
        delegate.hideWindow()
    }
}

// MARK: - Clipboard Row

/// A single row in the clipboard history list.
///
/// Extracted to keep the ForEach body readable. Displays either a
/// text snippet (up to 4 lines) or an image thumbnail, plus a
/// relative timestamp.
private struct ClipboardRow: View {

    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item.contentType {
            case .text:
                // `.lineLimit(4)` prevents a huge copied code block
                // from blowing out the layout.
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
            Text(item.copiedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Double Click Modifier

/// A view modifier that attaches a double-click gesture handler
/// using AppKit's `NSClickGestureRecognizer`.
///
/// SwiftUI does not provide a built-in double-click modifier for
/// macOS List rows. Using `.onTapGesture(count: 2)` conflicts with
/// the List's built-in single-click selection handling. Instead, we
/// overlay an AppKit gesture recognizer that only fires on double-click,
/// without interfering with the List's native click behavior.
private struct DoubleClickModifier: ViewModifier {

    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            DoubleClickOverlay(action: action)
        }
    }
}

/// An `NSViewRepresentable` that attaches a double-click gesture
/// recognizer to a transparent overlay view. The overlay is
/// hit-test transparent for single clicks (so List selection works
/// normally) and only fires the action on a double-click.
private struct DoubleClickOverlay: NSViewRepresentable {

    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DoubleClickView()
        let recognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onDoubleClick)
        )
        recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func onDoubleClick() {
            action()
        }
    }
}

/// A transparent NSView subclass that allows single clicks to pass
/// through to the underlying List (for selection) but catches double-
/// clicks via the attached gesture recognizer.
private class DoubleClickView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension View {
    /// Attaches a double-click handler to a view.
    func onDoubleClick(perform action: @escaping () -> Void) -> some View {
        modifier(DoubleClickModifier(action: action))
    }
}

#Preview {
    HomeView().environmentObject(AppState())
}

import SwiftUI
import AppKit

/// Displays a thumbnail for a locally stored image file.
///
/// Loads the image lazily when the row first appears on screen,
/// and caches it in `@State` so SwiftUI does not re-decode the
/// PNG on every redraw. If the file is missing or unreadable,
/// shows a native SF Symbols placeholder.
///
/// The thumbnail preserves the image's aspect ratio and is
/// capped at a modest height to keep the list compact.
struct ThumbnailView: View {

    /// The absolute path to the PNG file on disk.
    let path: String

    /// The decoded image, loaded once on appear.
    /// `@State` ensures the value survives SwiftUI redraws
    /// without re-triggering the file load.
    @State private var loadedImage: NSImage?

    /// Tracks whether we've already attempted to load.
    /// Prevents re-trying on every appear if the file is missing.
    @State private var didLoad = false

    var body: some View {
        Group {
            if let nsImage = loadedImage {
                // `Image(nsImage:)` wraps an AppKit `NSImage` for SwiftUI.
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 80)
                    // Rounded corners for a clean look.
                    .cornerRadius(4)
            } else {
                // Placeholder shown when the file is missing or hasn't loaded.
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
            }
        }
        .onAppear {
            loadIfNeeded()
        }
    }

    /// Loads the image from disk on first appearance.
    ///
    /// `NSImage(contentsOfFile:)` reads and decodes the file.
    /// The result is stored in `@State` so subsequent redraws
    /// reuse the decoded image without touching the file system.
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        loadedImage = NSImage(contentsOfFile: path)
    }
}

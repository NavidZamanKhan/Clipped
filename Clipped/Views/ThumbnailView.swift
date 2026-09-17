import SwiftUI
import AppKit
import ImageIO

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

    /// Loads a downsampled thumbnail from disk on first appearance using ImageIO.
    ///
    /// Rather than decoding full 4K/5K resolution screenshots into RAM (which consumes
    /// 25-50 MB per image), `CGImageSourceCreateThumbnailAtIndex` decodes ONLY the
    /// pixels needed for the thumbnail (capped at 200px max pixel size). This reduces
    /// memory usage from ~25-50 MB down to ~150 KB per image (a 99% reduction).
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 200
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            loadedImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}

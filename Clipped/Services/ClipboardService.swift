import AppKit

/// Reads content from the macOS system clipboard.
///
/// In macOS, the clipboard is called `NSPasteboard`. The "general"
/// pasteboard is the one used by ⌘C / ⌘V — similar to
/// `Clipboard.getData()` in Flutter.
///
/// This is a simple struct with static functions. There is no
/// need for a class or instance because we aren't storing any state —
/// we just reach into the system pasteboard, grab the content, and return it.
struct ClipboardService {

    /// Returns the current plain-text content of the system clipboard,
    /// or `nil` if the clipboard doesn't contain plain text.
    ///
    /// `NSPasteboard.general` is the shared system pasteboard.
    /// `string(forType: .string)` asks for plain-text data specifically.
    /// It returns an optional `String?` — `nil` means "no plain text available."
    static func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Returns the current image on the system clipboard, or `nil`
    /// if the clipboard doesn't contain an image.
    ///
    /// Checks for PNG data first (lossless, most screenshots produce this),
    /// then falls back to TIFF data (AppKit's native image format).
    /// The result is an `NSImage` that the caller can convert to PNG
    /// for persistence.
    static func currentImage() -> NSImage? {
        let pasteboard = NSPasteboard.general

        // Prefer native PNG data — screenshots and most image copies
        // place PNG on the pasteboard.
        if let pngData = pasteboard.data(forType: .png) {
            return NSImage(data: pngData)
        }

        // Fall back to TIFF — AppKit's internal image representation.
        // Many apps put TIFF data on the pasteboard alongside other types.
        if let tiffData = pasteboard.data(forType: .tiff) {
            return NSImage(data: tiffData)
        }

        return nil
    }
}

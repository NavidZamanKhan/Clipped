import AppKit
import os

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

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "ClipboardService"
    )

    /// Returns the current plain-text content of the system clipboard,
    /// or `nil` if the clipboard doesn't contain plain text.
    ///
    /// `NSPasteboard.general` is the shared system pasteboard.
    /// `string(forType: .string)` asks for plain-text data specifically.
    /// It returns an optional `String?` — `nil` means "no plain text available."
    static func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Returns the current file URL on the system clipboard, or `nil`
    /// if the clipboard doesn't contain a real file object reference.
    ///
    /// Requires native file pasteboard types (`.fileURL` or `NSFilenamesPboardType`).
    /// Plain-text strings containing URLs are strictly ignored so plain text is not misclassified.
    static func currentFileURL() -> URL? {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []

        let hasFileType = types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        guard hasFileType else { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first,
           url.isFileURL {
            return url
        }

        return nil
    }

    /// Returns the raw PNG data directly from the system clipboard if available,
    /// avoiding redundant image decompression and re-compression cycles.
    static func currentPNGData() -> Data? {
        NSPasteboard.general.data(forType: .png)
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

    // MARK: - Restore

    /// Writes plain text to the system clipboard, replacing its current
    /// contents. Used when the user restores a historical text clip.
    static func restoreText(_ text: String) {
        print("[TRACE] ClipboardService: restoreText() entered")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Writes an image (loaded from a file path) to the system clipboard.
    /// Used when the user restores a historical image clip.
    ///
    /// Reads the raw PNG data directly from disk to avoid running expensive
    /// CPU software PNG re-compression on the main thread. Also provides
    /// TIFF data for receiving applications that require TIFF.
    static func restoreImage(fromPath path: String) {
        print("[TRACE] ClipboardService: restoreImage() entered")
        let fileURL = URL(fileURLWithPath: path)
        guard let pngData = try? Data(contentsOf: fileURL) else {
            Self.logger.error("Failed to load image from path: \(path)")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        // For apps that prefer TIFF (e.g. Photoshop, Office), extract tiffRepresentation
        // without re-running PNG compression algorithms.
        if let image = NSImage(data: pngData), let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
    }

    /// Writes a file URL reference to the system clipboard.
    /// Used when the user restores a historical file clip.
    ///
    /// Writes the file reference using `pasteboard.writeObjects([fileURL as NSURL])`
    /// so Finder and other macOS apps recognize it as a copied file.
    static func restoreFile(atPath path: String) {
        print("[TRACE] ClipboardService: restoreFile() entered for path: \(path)")

        guard FileManager.default.fileExists(atPath: path) else {
            Self.logger.warning("Attempted to restore file that no longer exists at path: \(path)")
            return
        }

        let fileURL = URL(fileURLWithPath: path)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
    }
}

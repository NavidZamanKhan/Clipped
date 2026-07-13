import AppKit
import Foundation
import os

/// Handles reading and writing PNG image files for clipboard history.
///
/// All images are stored in:
///   Application Support/Clipped/Images/<uuid>.png
///
/// This struct has no instance state — all methods are static helpers.
struct ImageStorage {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "ImageStorage"
    )

    /// Returns the URL to the Images directory, creating it if needed.
    ///
    /// Returns `nil` if the directory cannot be located or created.
    static func imagesDirectoryURL() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let imagesDir = appSupport
            .appendingPathComponent("Clipped", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: imagesDir,
                withIntermediateDirectories: true
            )
            return imagesDir
        } catch {
            Self.logger.error("Failed to create Images directory: \(error)")
            return nil
        }
    }

    /// Converts an `NSImage` to PNG data and writes it atomically to disk.
    ///
    /// - Returns: The absolute file path on success, or `nil` on failure.
    ///
    /// The write uses `.atomic` so the file either appears completely
    /// or not at all — no partial/corrupt PNGs on disk.
    static func saveImage(_ image: NSImage) -> String? {
        guard let imagesDir = imagesDirectoryURL() else { return nil }

        // Get a bitmap representation from the image.
        // `NSImage.tiffRepresentation` is the standard way to extract
        // raw pixel data from any NSImage, regardless of source format.
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            Self.logger.error("Failed to convert image to PNG data")
            return nil
        }

        let filename = UUID().uuidString + ".png"
        let fileURL = imagesDir.appendingPathComponent(filename)

        do {
            // `.atomic` writes to a temporary file first, then renames.
            // This prevents partial writes if the app crashes mid-save.
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            Self.logger.error("Failed to write PNG file: \(error)")
            return nil
        }
    }

    /// Deletes an image file at the given path.
    ///
    /// Fails silently if the file is already gone — this is intentional
    /// so that cleanup during FIFO trim doesn't crash on missing files.
    static func deleteImage(at path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            // File may already have been deleted; that's fine.
            Self.logger.warning("Could not delete \(path): \(error)")
        }
    }
}

import AppKit
import os

/// Monitors the macOS clipboard for new plain-text or image content.
///
/// macOS does not provide a notification when the clipboard changes.
/// Instead, `NSPasteboard` exposes a `changeCount` integer that increments
/// every time any app writes to the clipboard. We poll it on a timer —
/// this is the standard approach used by native macOS clipboard utilities.
///
/// This is a `class` (not a `struct`) because it holds mutable state:
/// the running `Timer`, the last-seen `changeCount`, and the callbacks.
/// In Flutter terms, this is like a controller that you `dispose()` of
/// when the widget unmounts — here, you call `stop()`.
class ClipboardMonitor {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "ClipboardMonitor"
    )

    /// The timer that periodically checks for clipboard changes.
    /// `Timer` is Swift's equivalent of Dart's `Timer.periodic`.
    private var timer: Timer?

    /// The last `changeCount` we observed. If the current value differs,
    /// someone has written to the clipboard since we last checked.
    private var lastChangeCount: Int = 0

    /// The specific `NSPasteboard.changeCount` value to ignore.
    ///
    /// Set by the paste-restoration flow *after* writing to the
    /// pasteboard. When the monitor detects this exact changeCount,
    /// it silently consumes the change and clears this value.
    /// More robust than a boolean flag because it matches the
    /// *specific* change, not just "the next one."
    var ignoredChangeCount: Int?

    /// Called when new non-empty plain text is detected on the clipboard.
    private var onNewText: ((String) -> Void)?

    /// Called when a new image is detected on the clipboard.
    private var onNewImage: ((NSImage) -> Void)?

    /// Called when a file URL reference is detected on the clipboard.
    private var onNewFile: ((URL) -> Void)?

    /// Begins polling the clipboard at a 1-second interval.
    ///
    /// Each clipboard change is treated as mutually exclusive:
    /// File URL is checked first (since Finder copies put plain-text path fallbacks on the pasteboard).
    /// If no file URL is found, plain text is checked. If no plain text is found, image is checked.
    ///
    /// - Parameters:
    ///   - onNewText: Called with the new text when plain text is detected.
    ///   - onNewImage: Called with the new image when an image is detected.
    ///   - onNewFile: Called with the file URL when a file reference is detected.
    func start(
        onNewText: @escaping (String) -> Void,
        onNewImage: @escaping (NSImage) -> Void,
        onNewFile: @escaping (URL) -> Void
    ) {
        self.onNewText = onNewText
        self.onNewImage = onNewImage
        self.onNewFile = onNewFile

        // Snapshot the current changeCount so we don't immediately
        // re-report whatever is already on the clipboard at launch.
        lastChangeCount = NSPasteboard.general.changeCount

        // `scheduledTimer` creates and starts a repeating timer.
        // `withTimeInterval: 1.0` means it fires every second.
        // `[weak self]` prevents a retain cycle — if the monitor is
        // deallocated, the closure won't keep it alive. This is like
        // checking `mounted` in a Flutter StatefulWidget before calling
        // `setState`.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }

        Self.logger.info("Clipboard monitoring started")
    }

    /// Stops the timer. Called when the application quits.
    ///
    /// `invalidate()` permanently stops the timer and removes it from the
    /// run loop. Setting it to `nil` releases the reference.
    func stop() {
        timer?.invalidate()
        timer = nil
        Self.logger.info("Clipboard monitoring stopped")
    }

    // MARK: - Private

    /// Compares the current `changeCount` to our stored value.
    /// If different, reads the clipboard and calls the appropriate callback.
    ///
    /// Priority 1: File URL (checked BEFORE plain text, because file copies in Finder include plain-text path fallbacks).
    /// Priority 2: Plain text.
    /// Priority 3: Image.
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        // If the count hasn't changed, nothing was copied — skip.
        guard currentCount != lastChangeCount else { return }

        // Update our snapshot so we don't process this change again.
        lastChangeCount = currentCount

        // If this changeCount matches our own pasteboard write,
        // consume it silently. This prevents Clipped's clipboard
        // restoration from creating a duplicate history entry.
        if let ignored = ignoredChangeCount, currentCount == ignored {
            ignoredChangeCount = nil
            Self.logger.debug("Skipped self-initiated clipboard change (count=\(currentCount))")
            return
        }

        // Priority 1: File URL (must be checked BEFORE plain text).
        if let fileURL = ClipboardService.currentFileURL() {
            onNewFile?(fileURL)
            return
        }

        // Priority 2: Plain text.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            onNewText?(text)
            return
        }

        // Priority 3: Image (PNG preferred, TIFF fallback).
        if let image = ClipboardService.currentImage() {
            onNewImage?(image)
            return
        }
    }
}

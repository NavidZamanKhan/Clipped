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

    /// Called when new non-empty plain text is detected on the clipboard.
    private var onNewText: ((String) -> Void)?

    /// Called when a new image is detected on the clipboard.
    private var onNewImage: ((NSImage) -> Void)?

    /// Begins polling the clipboard at a 1-second interval.
    ///
    /// Each clipboard change is treated as mutually exclusive:
    /// text is checked first. If non-empty text is found, the image
    /// check is skipped. This matches user expectations when an app
    /// puts both text and image representations on the pasteboard.
    ///
    /// - Parameters:
    ///   - onNewText: Called with the new text when plain text is detected.
    ///   - onNewImage: Called with the new image when an image is detected
    ///     and no plain text was found.
    func start(
        onNewText: @escaping (String) -> Void,
        onNewImage: @escaping (NSImage) -> Void
    ) {
        self.onNewText = onNewText
        self.onNewImage = onNewImage

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
    /// Text is checked first. Only if no non-empty text is found do we
    /// check for an image. This ensures a single clipboard event produces
    /// at most one history entry.
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        // If the count hasn't changed, nothing was copied — skip.
        guard currentCount != lastChangeCount else { return }

        // Update our snapshot so we don't process this change again.
        lastChangeCount = currentCount

        // Priority 1: plain text.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            onNewText?(text)
            return
        }

        // Priority 2: image (PNG preferred, TIFF fallback).
        if let image = ClipboardService.currentImage() {
            onNewImage?(image)
        }
    }
}

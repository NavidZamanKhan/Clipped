import AppKit

/// Monitors the macOS clipboard for new plain-text content.
///
/// macOS does not provide a notification when the clipboard changes.
/// Instead, `NSPasteboard` exposes a `changeCount` integer that increments
/// every time any app writes to the clipboard. We poll it on a timer —
/// this is the standard approach used by native macOS clipboard utilities.
///
/// This is a `class` (not a `struct`) because it holds mutable state:
/// the running `Timer`, the last-seen `changeCount`, and the callback.
/// In Flutter terms, this is like a controller that you `dispose()` of
/// when the widget unmounts — here, you call `stop()`.
class ClipboardMonitor {

    /// The timer that periodically checks for clipboard changes.
    /// `Timer` is Swift's equivalent of Dart's `Timer.periodic`.
    private var timer: Timer?

    /// The last `changeCount` we observed. If the current value differs,
    /// someone has written to the clipboard since we last checked.
    private var lastChangeCount: Int = 0

    /// Called when new non-empty plain text is detected on the clipboard.
    private var onNewText: ((String) -> Void)?

    /// Begins polling the clipboard at a 1-second interval.
    ///
    /// - Parameter onNewText: A closure called with the new text each time
    ///   a clipboard change is detected. This runs on the main thread
    ///   because `Timer.scheduledTimer` fires on the current run loop
    ///   (which is the main run loop when called from SwiftUI).
    func start(onNewText: @escaping (String) -> Void) {
        self.onNewText = onNewText

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
    }

    /// Stops the timer. Call this when the view disappears or the app quits.
    ///
    /// `invalidate()` permanently stops the timer and removes it from the
    /// run loop. Setting it to `nil` releases the reference.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    /// Compares the current `changeCount` to our stored value.
    /// If different, reads the clipboard and calls the callback.
    private func checkForChanges() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        // If the count hasn't changed, nothing was copied — skip.
        guard currentCount != lastChangeCount else { return }

        // Update our snapshot so we don't process this change again.
        lastChangeCount = currentCount

        // Read plain text from the clipboard. `string(forType: .string)`
        // returns nil if the clipboard doesn't contain plain text (e.g.,
        // the user copied an image).
        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty else {
            return
        }

        onNewText?(text)
    }
}

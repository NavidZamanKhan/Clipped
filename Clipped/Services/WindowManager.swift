import AppKit
import SwiftUI
import os

// MARK: - ClippedPanel

/// A dedicated NSPanel subclass for Clipped's launcher UI.
///
/// Subclassing NSPanel rather than using a bare instance serves one
/// critical purpose: it makes `canBecomeKey` an unconditional contract,
/// independent of styleMask. A bare NSPanel returns `false` for
/// `canBecomeKey` when the `.titled` style is absent, silently breaking
/// keyboard input for any future visual customisation. Overriding here
/// makes the guarantee explicit and permanent.
///
/// `canBecomeMain` is explicitly `false` — Clipped is a floating panel,
/// not a document window. Main-window status is irrelevant here and
/// should never be granted.
private final class ClippedPanel: NSPanel {

    /// Unconditionally allows this panel to become the key window.
    ///
    /// A window must be key for keyboard events to reach its responder
    /// chain. Without this override, removing `.titled` from the styleMask
    /// would silently kill all keyboard input (↑ ↓ Enter Escape).
    override var canBecomeKey: Bool  { true  }

    /// Prevents this panel from ever becoming the main window.
    ///
    /// Panels are auxiliary floating UI — they are never the document
    /// or primary window of the application.
    override var canBecomeMain: Bool { false }
}

// MARK: - WindowManager

/// Owns and manages Clipped's permanent floating panel.
///
/// The panel is created exactly once in `createPanel(appState:)`, called
/// from `AppDelegate.applicationDidFinishLaunching`. Every subsequent
/// show/hide is a simple order-front / order-out on the same panel
/// instance — no reconstruction of the SwiftUI hierarchy, no SQLite
/// reads, no expensive work.
///
/// # Lifecycle
///
/// ```
/// applicationDidFinishLaunching
///   └── createPanel(appState:)    ← one time only
///
/// user triggers hotkey / menu bar
///   └── showPanel()               ← near instant
///
/// user presses Escape or Enter
///   └── hidePanel()               ← near instant
/// ```
///
/// # Memory ownership
///
/// `AppDelegate` holds `WindowManager` strongly (let).
/// `WindowManager` holds `ClippedPanel` and `NSHostingController` strongly (var).
/// `WindowManager` holds `AppState` weakly — AppDelegate owns AppState.
/// The panel has no back-reference to `WindowManager`. No retain cycles.
final class WindowManager {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "WindowManager"
    )

    // MARK: - Private State

    /// The permanent panel. Created once; never recreated.
    private var panel: ClippedPanel?

    /// The permanent SwiftUI hosting controller.
    /// Creating this once prevents SwiftUI from rebuilding its view
    /// hierarchy on every show. The tree stays alive for the app's lifetime.
    private var hostingController: NSHostingController<AnyView>?

    /// Weak reference to AppState. AppDelegate owns AppState; WindowManager
    /// only borrows it. Using `weak` prevents a retain cycle even though
    /// AppDelegate → WindowManager → AppState → AppDelegate (via NSApp.delegate)
    /// is not actually a direct cycle — `weak` is correct practice here.
    private weak var appState: AppState?

    /// The local event monitor for Return and Escape keyboard shortcuts.
    ///
    /// Installed when the panel is shown; removed when hidden. The monitor
    /// fires BEFORE the responder chain, intercepting key events before
    /// `NSTableView` (backing SwiftUI's List) can consume them.
    ///
    /// Stored as `Any?` because `NSEvent.addLocalMonitorForEvents` returns
    /// an opaque object that must be passed to `NSEvent.removeMonitor`.
    private var keyMonitor: Any?

    // MARK: - Panel Creation

    /// Creates the panel and embeds the SwiftUI content view.
    ///
    /// Must be called exactly once, during `applicationDidFinishLaunching`,
    /// before any `showPanel()` call. Subsequent calls are guarded and
    /// produce a warning.
    ///
    /// - Parameter appState: The shared UI state. Injected as an
    ///   `@EnvironmentObject` into the SwiftUI tree hosted inside the panel.
    func createPanel(appState: AppState) {
        guard panel == nil else {
            Self.logger.warning("createPanel called more than once — ignoring")
            return
        }

        self.appState = appState

        // MARK: Panel Geometry
        //
        // Position the panel in the upper-centre of the primary screen,
        // matching Spotlight's placement. If no screen is available (rare
        // edge case during headless testing), fall back to a fixed rect.
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth:  CGFloat = 420
        let panelHeight: CGFloat = 600
        let originX = screenFrame.midX - panelWidth  / 2
        let originY = screenFrame.maxY - panelHeight - 80   // 80pt from top, like Spotlight
        let contentRect = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)

        // MARK: Panel Initialisation
        //
        // Style flags explained:
        //   .titled              — required for the default canBecomeKey = true
        //                         path; also lets us use fullSizeContentView cleanly.
        //   .fullSizeContentView — SwiftUI content extends under the (hidden) title bar.
        //   .nonactivatingPanel  — the panel can appear and become key WITHOUT
        //                         automatically activating the application. We still
        //                         call NSApp.activate explicitly in showPanel() — the
        //                         flag's value is that it doesn't disrupt the previous
        //                         app's window ordering when we appear.
        let newPanel = ClippedPanel(
            contentRect: contentRect,
            styleMask:   [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        // Float above normal document windows.
        newPanel.level = .floating

        // True panel behaviour: floats above all other windows at its level.
        newPanel.isFloatingPanel = true

        // We control visibility explicitly with orderOut/makeKeyAndOrderFront.
        // If this were true, the panel would hide whenever Clipped deactivates
        // (e.g. user switches apps), which is not what we want.
        newPanel.hidesOnDeactivate = false

        // CRITICAL: prevents NSPanel from deallocating itself when orderOut
        // is called. Without this, the panel is released on first hide and
        // the next showPanel() call crashes or silently fails.
        newPanel.isReleasedWhenClosed = false

        // Follow the user across Mission Control Spaces and work in
        // full-screen apps. This matches Spotlight's collection behaviour.
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Visual polish: transparent title bar so SwiftUI content owns the
        // full window chrome. Title text is hidden; we provide our own header.
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden

        // Disable the traffic-light close/minimise/zoom buttons.
        // Clipped is dismissed via Escape or Enter, never the close button.
        newPanel.standardWindowButton(.closeButton)?.isHidden    = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden      = true

        // MARK: SwiftUI Embedding
        //
        // Build the SwiftUI tree once. AnyView type-erases the concrete
        // View type so we can store it as a typed property without generics
        // on WindowManager itself.
        let rootView = AnyView(
            HomeView()
                .environmentObject(appState)
        )

        let controller = NSHostingController(rootView: rootView)
        controller.view.frame = contentRect

        newPanel.contentViewController = controller

        // Retain both the panel and the controller for the app's lifetime.
        self.panel             = newPanel
        self.hostingController = controller

        Self.logger.info("Panel created — size \(Int(panelWidth))×\(Int(panelHeight))")
    }

    // MARK: - Show

    /// Shows the panel and transfers keyboard focus to it.
    ///
    /// The sequence is intentional and order-sensitive:
    ///
    /// 1. `selectNewest()` — sets the correct selection state *before* the
    ///    panel becomes visible. Avoids a flash of wrong-selection state.
    ///
    /// 2. `makeKeyAndOrderFront` — brings the panel to the front of the
    ///    window list and makes it the key window. After this call,
    ///    keyboard events route to the panel's responder chain.
    ///
    /// 3. `NSApp.activate` — makes Clipped the active application.
    ///    Required even with `.nonactivatingPanel`: that flag only suppresses
    ///    *automatic* activation on click/show. For a hotkey-triggered,
    ///    keyboard-first panel we *want* explicit activation so that
    ///    our key window receives events immediately.
    func showPanel() {
        guard let panel else {
            Self.logger.error("showPanel called before createPanel — panel is nil")
            return
        }

        // 1. Deterministic selection — synchronous, before any rendering.
        appState?.selectNewest()

        // 2. Bring panel forward and make it key.
        panel.makeKeyAndOrderFront(nil)

        // 3. Activate the application so key events reach the panel.
        NSApp.activate(ignoringOtherApps: true)

        // 4. Install the keyboard monitor so Return and Escape work.
        installKeyMonitor()

        Self.logger.debug("Panel shown")
    }

    // MARK: - Hide

    /// Hides the panel and returns focus to the previously active application.
    ///
    /// `orderOut` removes the panel from the window list without closing or
    /// deallocating it. The panel remains in memory, ready for the next show.
    ///
    /// `NSApp.hide(nil)` deactivates Clipped. macOS then automatically
    /// reactivates the application that was active before Clipped appeared.
    /// This is the same mechanism used by Alfred and Raycast.
    func hidePanel() {
        print("[TRACE] WindowManager: hidePanel() entered")
        removeKeyMonitor()
        panel?.orderOut(nil)
        NSApp.hide(nil)
        Self.logger.debug("Panel hidden")
    }

    // MARK: - Key Monitor

    /// Installs a local event monitor that intercepts Return and Escape
    /// BEFORE they reach the responder chain.
    ///
    /// This is the correct AppKit API for keyboard-first launcher utilities.
    /// The same pattern is used by Maccy, Alfred, and Raycast.
    ///
    /// The monitor:
    /// - Catches Return (keyCode 36) → triggers paste
    /// - Catches Escape (keyCode 53) → triggers hide
    /// - Returns all other key events unchanged → normal responder chain
    ///
    /// The `[weak self]` capture prevents a retain cycle between the
    /// monitor closure and `WindowManager`.
    private func installKeyMonitor() {
        // Guard against double-install if showPanel() is called twice
        // without an intervening hidePanel().
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else {
                return event  // Not our panel — pass through unchanged.
            }

            switch event.keyCode {
            case 36:  // Return / Enter
                print("[TRACE] WindowManager: keyMonitor intercepted Return")
                self.performPaste()
                return nil   // Consumed — never reaches NSTableView.

            case 53:  // Escape
                print("[TRACE] WindowManager: keyMonitor intercepted Escape")
                self.performHide()
                return nil   // Consumed.

            default:
                return event // Arrow keys, Page Up/Down, etc. pass through.
            }
        }

        Self.logger.debug("Key monitor installed")
    }

    /// Removes the local event monitor. Called in `hidePanel()` so that
    /// key events are not intercepted while the panel is hidden.
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
            Self.logger.debug("Key monitor removed")
        }
    }

    // MARK: - Key Actions

    /// Routes Return key to AppDelegate's paste pipeline.
    ///
    /// Uses the same `NSApp.delegate as? AppDelegate` pattern that
    /// HomeView's double-click handler uses. This is the standard
    /// AppKit way to reach the app delegate from non-SwiftUI code.
    private func performPaste() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.pasteSelectedItem()
    }

    /// Routes Escape key to AppDelegate's hide method.
    private func performHide() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.hideWindow()
    }
}

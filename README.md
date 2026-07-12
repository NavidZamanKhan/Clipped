# Clipped

A fast, lightweight, native clipboard manager for macOS.

## Introduction

Clipped is a native macOS utility born out of a personal need for a simple, lightweight, and fast clipboard manager. Built as a side project and learning experience, its philosophy is simple: be fast, lightweight, local-only, and private. It features no accounts, cloud sync, analytics, AI, subscriptions, Electron, Flutter, or third-party frameworks.

### Why Native?

Many modern clipboard managers are built with heavy web technologies like Electron, require recurring subscriptions, or sync your private clipboard data to the cloud. Clipped is built entirely with Swift and Apple's native frameworks (SwiftUI and AppKit). This ensures a minimal memory footprint, blazing-fast performance, and a UI that feels perfectly at home on macOS.

## Current Features

- **Continuous Monitoring:** Silently monitors the macOS clipboard for text and image changes while the app is running.
- **Unified History:** Displays both text snippets and images in a single, unified, newest-first list.
- **Persistent Storage:** Saves your clipboard history locally using SQLite so your clips survive app restarts.
- **Image Support:** Automatically extracts and saves copied raster images (like screenshots) as local PNG files, managing them alongside text clips.
- **Auto-Cleanup:** Intelligently manages disk space by enforcing strict limits on how many clips are saved (older clips are automatically pruned).
- **Sandboxed:** All data is strictly contained within the app’s standard Application Support sandbox.

## How It Works Under the Hood

- **Clipboard Monitoring:** macOS doesn't broadcast notifications when the clipboard changes. Clipped handles this natively by running a 1-second interval timer that polls `NSPasteboard.general.changeCount`. When the count increments, the app knows another application has copied something.
- **Data Storage (SQLite):** It uses a lightweight `sqlite3` database to store metadata for every copied item (timestamp, type, and text content). The database is located at `~/Library/Application Support/Clipped/clipped.sqlite`.
- **Image Handling:** Images are not stuffed into the database. Instead, they are saved as independent `.png` files in the Application Support directory, and only their file path is referenced in the SQLite database.

## Privacy and Data Storage

All clipboard data is local-only and private. History is stored locally within the app's Application Support sandbox.

**Note:** Clipboard history may contain sensitive material such as passwords, API keys, OTPs, or private screenshots. It is stored locally, but currently should be treated as unencrypted local history.

## History Limits

To prevent your hard drive from filling up with thousands of large screenshots, Clipped enforces strict independent limits:

| Media Type | Limit       |
| ---------- | ----------- |
| Text       | 100 entries |
| Images     | 20 entries  |

## Current Limitations

- **Missed Copies:** Clipped cannot recover multiple things copied while it was closed; macOS only exposes the current clipboard item at launch.
- **Unencrypted Storage:** Clipboard history is stored locally, but it is currently unencrypted.
- **Window Mode Only:** The app is currently a normal development-window app, not yet a finished menu-bar utility.

## Getting Started

To build from source:

### Requirements

- macOS 26.5+ (as configured in the project)
- Xcode (Swift 5.0)

### Instructions

1. Open the `Clipped.xcodeproj` in Xcode.
2. Build and run with `⌘R`.

## Technology Stack

- **Swift & SwiftUI:** For the core application logic and user interface.
- **AppKit:** For interacting with the macOS `NSPasteboard` and handling native image representations (`NSImage`).
- **SQLite3:** Used directly via the C API for ultra-fast, dependency-free local data storage.

## Roadmap (Planned — Not Implemented)

The following features are planned for future development but are not currently implemented:

- Menu-bar mode (living in the status bar instead of the Dock)
- Global shortcut support to summon the clipboard anywhere
- Automatic paste functionality upon selecting a clip
- Launch at login
- Settings interface to configure limits and behaviors
- Compiled releases
- Homebrew distribution
- App Store distribution

## Contributing

Issues, feedback, and pull requests are welcome! Feel free to open an issue to discuss bugs or suggestions.

## License

No license has been selected for this repository yet.

# Clipped

A fast, lightweight, native clipboard manager for macOS.

## Introduction

Clipped is a native macOS utility born out of a personal need for a simple, lightweight, and fast clipboard manager. Built as a side project and learning experience, its philosophy is simple: be fast, lightweight, local-only, and private. It features no accounts, cloud sync, analytics, AI, subscriptions, Electron, Flutter, or third-party frameworks.

## Current Features

- Monitors the macOS clipboard while Clipped is running.
- Saves plain-text clipboard history locally with SQLite.
- Saves copied raster images (such as screenshots) as local PNG files, with metadata in SQLite.
- Restores history after Clipped is restarted.
- Shows text and image history in one newest-first list.
- Existing history is stored locally inside the app’s Application Support sandbox.
- The app is currently a normal development-window app, not yet a finished menu-bar utility.

## Privacy and Data Storage

All clipboard data is local-only and private. History is stored locally within the app's Application Support sandbox.

**Note:** Clipboard history may contain sensitive material such as passwords, API keys, OTPs, or private screenshots. It is stored locally, but currently should be treated as unencrypted local history. 

## History Limits

| Media Type | Limit |
| --- | --- |
| Text | 100 entries |
| Images | 20 entries |

## Current Limitations

- **Missed Copies:** Clipped cannot recover multiple things copied while it was closed; macOS only exposes the current clipboard item at launch.
- **Unencrypted Storage:** Clipboard history is stored locally, but it is currently unencrypted.

## Getting Started

To build from source:

### Requirements
- macOS 26.5+ (as configured in the project)
- Xcode (Swift 5.0)

### Instructions
1. Open the `Clipped.xcodeproj` in Xcode.
2. Build and run with `⌘R`.

## Technology

- Swift & SwiftUI
- SQLite3
- Native macOS frameworks

## Roadmap (Planned — Not Implemented)

The following features are planned for future development but are not currently implemented:

- Menu-bar mode
- Global shortcut support
- Automatic paste functionality
- Launch at login
- Settings interface
- Compiled releases
- Homebrew distribution
- App Store distribution

## Contributing

Issues, feedback, and pull requests are welcome! Feel free to open an issue to discuss bugs or suggestions.

## License

No license has been selected for this repository yet.

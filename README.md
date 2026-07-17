# Clipped

A lightweight, native clipboard manager for macOS built with Swift and SwiftUI.

Clipped is designed to feel like a first-party macOS utility. It runs quietly in the background, automatically captures clipboard history, and provides instant access to recently copied content without unnecessary features or complexity.

## Features

- Native macOS application built with SwiftUI and AppKit
- Runs as a menu bar utility with a global shortcut (`Shift+Command+V`)
- Automatic clipboard history
- Persistent clipboard storage using SQLite
- Image clipboard support
- Search clipboard history (press `/` to focus search)
- Lightweight and keyboard-focused (↑/↓ to navigate, Enter to paste, Esc to hide)
- Local-first with no cloud services
- Privacy-friendly with all data stored on-device

## Tech Stack

- Swift 6
- SwiftUI
- AppKit
- SQLite
- NSPasteboard
- os.Logger

## Architecture

The project follows a lightweight architecture focused on simplicity and maintainability.

```
AppDelegate
├── ClipboardMonitor
├── ClipboardStore (SQLite)
├── MenuBarManager
├── WindowManager
└── AppState
```

Long-lived services are owned by the application delegate, while SwiftUI views consume a lightweight observable application state. Clipboard monitoring, persistence, and window management remain independent, keeping responsibilities clearly separated.

## Project Structure

```
Clipped/
├── App/
├── Models/
├── Services/
├── Views/
├── Utilities/
└── Resources/
```

## Requirements

- macOS 26 or later
- Xcode 26
- Swift 6

## Build

Clone the repository and open the project in Xcode.

```bash
git clone https://github.com/NavidZamanKhan/Clipped.git
cd Clipped
open Clipped.xcodeproj
```

Run the project using the **Clipped** scheme.

## License

This project is licensed under the MIT License.

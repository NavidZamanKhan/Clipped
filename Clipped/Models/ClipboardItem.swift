import Foundation

/// A single clipboard history entry.
///
/// This is a plain value type — similar to a simple data class in Dart/Kotlin.
///
/// `Identifiable` conformance gives each item a unique `id` property.
/// SwiftUI's `ForEach` uses this to track which row is which, just like
/// passing a `key` to widgets in a Flutter `ListView.builder`.
struct ClipboardItem: Identifiable {

    /// The SQLite `AUTOINCREMENT` primary key.
    let id: Int64

    /// The plain-text clipboard content.
    let text: String

    /// When this text was copied (or first seen by Clipped).
    let copiedAt: Date
}

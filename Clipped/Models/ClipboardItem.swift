import Foundation

/// Distinguishes between text and image clipboard entries.
///
/// The raw `String` values (`"text"`, `"image"`) are stored directly in
/// the SQLite `content_type` column, so no mapping layer is needed.
enum ContentType: String {
    case text  = "text"
    case image = "image"
}

/// A single clipboard history entry — either copied text or an image.
///
/// This is a plain value type — similar to a simple data class in Dart/Kotlin.
///
/// `Identifiable` conformance gives each item a unique `id` property.
/// SwiftUI's `ForEach` uses this to track which row is which, just like
/// passing a `key` to widgets in a Flutter `ListView.builder`.
struct ClipboardItem: Identifiable {

    /// The SQLite `AUTOINCREMENT` primary key.
    let id: Int64

    /// Whether this entry represents copied text or a copied image.
    let contentType: ContentType

    /// The plain-text clipboard content.
    /// For image entries this is an empty string.
    let text: String

    /// The absolute path to the locally saved PNG file.
    /// Only non-nil for image entries.
    let imagePath: String?

    /// When this text or image was copied (or first seen by Clipped).
    let copiedAt: Date
}

import Foundation

/// Distinguishes between text and image clipboard entries.
///
/// The raw `String` values (`"text"`, `"image"`) are stored directly in
/// the SQLite `content_type` column, so no mapping layer is needed.
enum ContentType: String {
    case text  = "text"
    case image = "image"
    case file  = "file"
}

/// A single clipboard history entry — either copied text, an image, or a file reference.
///
/// This is a plain value type — similar to a simple data class in Dart/Kotlin.
///
/// `Identifiable` conformance gives each item a unique `id` property.
/// SwiftUI's `ForEach` uses this to track which row is which, just like
/// passing a `key` to widgets in a Flutter `ListView.builder`.
struct ClipboardItem: Identifiable, Hashable {

    /// The SQLite `AUTOINCREMENT` primary key.
    let id: Int64

    /// Whether this entry represents copied text, an image, or a file.
    let contentType: ContentType

    /// The plain-text clipboard content.
    /// For image entries this is an empty string.
    /// For file entries this holds the file's display name / path representation.
    let text: String

    /// The absolute path to the locally saved PNG file.
    /// Only non-nil for image entries.
    let imagePath: String?

    /// The absolute file path on disk.
    /// Only non-nil for file entries.
    let filePath: String?

    /// When this item was copied (or first seen by Clipped).
    /// Mutable so that the timestamp can be updated when the user
    /// restores a historical item (which moves it to the top).
    var copiedAt: Date

    /// Whether this entry is pinned to stay at the top.
    var isPinned: Bool

    /// When this entry was pinned (used for dedicated pinned ordering).
    var pinnedAt: Date?

    init(
        id: Int64,
        contentType: ContentType,
        text: String,
        imagePath: String?,
        filePath: String? = nil,
        copiedAt: Date,
        isPinned: Bool = false,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.contentType = contentType
        self.text = text
        self.imagePath = imagePath
        self.filePath = filePath
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
    }
}

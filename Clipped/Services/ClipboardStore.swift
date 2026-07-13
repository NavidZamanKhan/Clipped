import SQLite3
import Foundation
import os

/// Manages the SQLite database for clipboard history.
///
/// This is a `class` (not a `struct`) because it holds an `OpaquePointer`
/// to the open SQLite database connection. That handle must be closed
/// exactly once when we're done — `deinit` handles that automatically.
///
/// In Flutter terms, think of this as a singleton database helper, except
/// here we just create one instance and hold onto it in the view's state.
///
/// All methods run on the main thread (`@MainActor` is the project default).
/// SQLite operations on ≤120 small rows are sub-millisecond, so there's
/// no need for background threads at this scale.
class ClipboardStore {

    private static let logger = Logger(
        subsystem: "com.NavidZamanKhan.Clipped",
        category: "ClipboardStore"
    )

    /// The maximum number of text clipboard items to retain.
    private let maxTextItems = 100

    /// The maximum number of image clipboard items to retain.
    private let maxImageItems = 20

    /// The open SQLite database handle. `OpaquePointer` is Swift's way of
    /// representing a C pointer whose underlying struct is hidden — like
    /// the `sqlite3 *` type in C.
    private var db: OpaquePointer?

    /// Opens (or creates) the SQLite database and ensures the table exists.
    ///
    /// The database lives at:
    ///   ~/Library/Application Support/Clipped/clipped.sqlite
    ///
    /// Because the app is sandboxed, macOS redirects this into the app's
    /// container automatically. The code is the same either way.
    init() {
        let fileManager = FileManager.default

        // `urls(for:in:)` returns an array, but there's always exactly one
        // Application Support directory. We grab it, then append our app's
        // subfolder.
        guard let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            Self.logger.error("Could not locate Application Support directory")
            return
        }

        let clippedDir = appSupport.appendingPathComponent("Clipped", isDirectory: true)

        // Create the directory if it doesn't exist. `withIntermediateDirectories`
        // is like `mkdir -p` — it won't fail if the folder is already there.
        do {
            try fileManager.createDirectory(at: clippedDir, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Failed to create directory: \(error)")
            return
        }

        let dbPath = clippedDir.appendingPathComponent("clipped.sqlite").path

        // `sqlite3_open` creates the file if it doesn't exist.
        // It returns SQLITE_OK (0) on success.
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            Self.logger.error("Failed to open database at \(dbPath)")
            return
        }

        createTableIfNeeded()
        migrateIfNeeded()
        Self.logger.info("Database opened at \(dbPath)")
    }

    /// Closes the database connection explicitly.
    ///
    /// Called by `AppDelegate.applicationWillTerminate` to ensure a clean
    /// shutdown. Safe to call multiple times — subsequent calls are no-ops.
    func close() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
        Self.logger.info("Database connection closed")
    }

    /// Closes the database connection when this object is deallocated.
    ///
    /// `deinit` is Swift's destructor — it runs automatically when the
    /// last reference to this object is released. Similar to calling
    /// `dispose()` on a Flutter controller, but you don't call it manually.
    ///
    /// Acts as a safety net if `close()` was not called explicitly.
    /// After `close()`, `db` is nil, so this is a no-op.
    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    /// Loads all clipboard items from the database, newest first.
    ///
    /// Uses stable ordering: `copied_at DESC, id DESC` so that items
    /// with identical timestamps are consistently ordered.
    func loadAll() -> [ClipboardItem] {
        let sql = """
            SELECT id, text, copied_at, content_type, image_path
            FROM clipboard_items
            ORDER BY copied_at DESC, id DESC;
            """
        var statement: OpaquePointer?

        // `sqlite3_prepare_v2` compiles the SQL string into a prepared
        // statement — like a pre-parsed query the database can execute
        // efficiently.
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare loadAll statement")
            return []
        }

        // `defer` ensures `sqlite3_finalize` runs when we leave this scope,
        // even if we return early. It's like a `finally` block in Dart.
        defer { sqlite3_finalize(statement) }

        var items: [ClipboardItem] = []

        // `sqlite3_step` advances the cursor to the next row.
        // It returns SQLITE_ROW when there's data, SQLITE_DONE when finished.
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)

            // `sqlite3_column_text` returns a C string (UnsafePointer<UInt8>).
            // We wrap it in `String(cString:)` to get a Swift String.
            let textPointer = sqlite3_column_text(statement, 1)
            let text = textPointer.map { String(cString: $0) } ?? ""

            let timestamp = sqlite3_column_double(statement, 2)
            let copiedAt = Date(timeIntervalSince1970: timestamp)

            // Read content_type; default to "text" for pre-migration rows.
            let typePointer = sqlite3_column_text(statement, 3)
            let typeString = typePointer.map { String(cString: $0) } ?? "text"
            let contentType = ContentType(rawValue: typeString) ?? .text

            // Read image_path (may be NULL for text entries).
            let pathPointer = sqlite3_column_text(statement, 4)
            let imagePath = pathPointer.map { String(cString: $0) }

            items.append(ClipboardItem(
                id: id,
                contentType: contentType,
                text: text,
                imagePath: imagePath,
                copiedAt: copiedAt
            ))
        }

        return items
    }

    /// Inserts a new clipboard text entry and returns the created item.
    ///
    /// Uses parameterized binding (`?` placeholder + `sqlite3_bind_text`)
    /// so that clipboard text containing quotes, SQL, JSON, emoji, or
    /// newlines is handled safely — no SQL injection possible.
    func insert(text: String) -> ClipboardItem? {
        let sql = """
            INSERT INTO clipboard_items (text, copied_at, content_type)
            VALUES (?, ?, 'text');
            """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare insert statement")
            return nil
        }

        defer { sqlite3_finalize(statement) }

        let now = Date()

        // Bind parameter 1: the clipboard text.
        // `-1` tells SQLite to compute the string length itself.
        // `SQLITE_TRANSIENT` tells SQLite to make its own copy of the string
        // data, so it's safe even if Swift deallocates the original.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, text, -1, transient)

        // Bind parameter 2: the timestamp as a Unix epoch double.
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            Self.logger.error("Failed to insert text item")
            return nil
        }

        let id = sqlite3_last_insert_rowid(db)
        return ClipboardItem(
            id: id,
            contentType: .text,
            text: text,
            imagePath: nil,
            copiedAt: now
        )
    }

    /// Inserts a new clipboard image entry and returns the created item.
    ///
    /// The PNG file must already exist at `path` before calling this.
    /// If the database insert fails, the caller should delete the file.
    func insertImage(path: String) -> ClipboardItem? {
        let sql = """
            INSERT INTO clipboard_items (text, copied_at, content_type, image_path)
            VALUES ('', ?, 'image', ?);
            """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare insertImage statement")
            return nil
        }

        defer { sqlite3_finalize(statement) }

        let now = Date()
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, path, -1, transient)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            Self.logger.error("Failed to insert image item")
            return nil
        }

        let id = sqlite3_last_insert_rowid(db)
        return ClipboardItem(
            id: id,
            contentType: .image,
            text: "",
            imagePath: path,
            copiedAt: now
        )
    }

    /// Deletes the oldest text items so that at most `maxTextItems` remain.
    ///
    /// This is the text FIFO trim: when the 101st text item is added,
    /// the oldest text entry is permanently removed from SQLite.
    /// Image entries are not affected.
    func trimText() {
        let sql = """
            DELETE FROM clipboard_items
            WHERE content_type = 'text'
            AND id NOT IN (
                SELECT id FROM clipboard_items
                WHERE content_type = 'text'
                ORDER BY copied_at DESC, id DESC
                LIMIT ?
            );
            """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare trimText statement")
            return
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(maxTextItems))

        if sqlite3_step(statement) != SQLITE_DONE {
            Self.logger.error("Failed to trim text items")
        }
    }

    /// Deletes the oldest image items so that at most `maxImageItems` remain.
    ///
    /// Returns an array of `(id, imagePath)` tuples for the deleted rows
    /// so that the caller can:
    /// 1. Remove those entries from the in-memory `items` array.
    /// 2. Delete the corresponding PNG files from disk.
    func trimImages() -> [(id: Int64, path: String)] {
        // First, find which image rows will be deleted.
        let selectSQL = """
            SELECT id, image_path FROM clipboard_items
            WHERE content_type = 'image'
            AND id NOT IN (
                SELECT id FROM clipboard_items
                WHERE content_type = 'image'
                ORDER BY copied_at DESC, id DESC
                LIMIT ?
            );
            """
        var selectStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare trimImages select statement")
            return []
        }

        defer { sqlite3_finalize(selectStmt) }

        sqlite3_bind_int(selectStmt, 1, Int32(maxImageItems))

        var deleted: [(id: Int64, path: String)] = []

        while sqlite3_step(selectStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(selectStmt, 0)
            let pathPointer = sqlite3_column_text(selectStmt, 1)
            let path = pathPointer.map { String(cString: $0) } ?? ""
            if !path.isEmpty {
                deleted.append((id: id, path: path))
            }
        }

        // If nothing to delete, return early.
        if deleted.isEmpty { return [] }

        // Now delete those rows from the database.
        let deleteSQL = """
            DELETE FROM clipboard_items
            WHERE content_type = 'image'
            AND id NOT IN (
                SELECT id FROM clipboard_items
                WHERE content_type = 'image'
                ORDER BY copied_at DESC, id DESC
                LIMIT ?
            );
            """
        var deleteStmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            Self.logger.error("Failed to prepare trimImages delete statement")
            return []
        }

        defer { sqlite3_finalize(deleteStmt) }

        sqlite3_bind_int(deleteStmt, 1, Int32(maxImageItems))

        if sqlite3_step(deleteStmt) != SQLITE_DONE {
            Self.logger.error("Failed to trim image items")
            return []
        }

        return deleted
    }

    // MARK: - Private

    /// Creates the `clipboard_items` table if it doesn't already exist.
    private func createTableIfNeeded() {
        let sql = """
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                copied_at REAL NOT NULL
            );
            """

        // `sqlite3_exec` is a convenience for one-shot statements that
        // don't return data. It compiles, runs, and finalizes in one call.
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            Self.logger.error("Failed to create table")
        }
    }

    /// Adds `content_type` and `image_path` columns if they don't exist.
    ///
    /// This is a non-destructive migration: existing text rows are
    /// untouched and automatically receive `content_type = 'text'`
    /// via the column's DEFAULT value.
    ///
    /// We check column existence via `PRAGMA table_info` rather than
    /// blindly running ALTER TABLE (which would fail if the column
    /// already exists).
    private func migrateIfNeeded() {
        let existingColumns = columnNames()

        if !existingColumns.contains("content_type") {
            let sql = """
                ALTER TABLE clipboard_items
                ADD COLUMN content_type TEXT NOT NULL DEFAULT 'text';
                """
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                Self.logger.error("Failed to add content_type column")
            }
        }

        if !existingColumns.contains("image_path") {
            let sql = """
                ALTER TABLE clipboard_items
                ADD COLUMN image_path TEXT;
                """
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                Self.logger.error("Failed to add image_path column")
            }
        }
    }

    /// Returns the set of column names in the `clipboard_items` table.
    private func columnNames() -> Set<String> {
        let sql = "PRAGMA table_info(clipboard_items);"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var names: Set<String> = []

        // PRAGMA table_info returns rows with columns:
        // cid, name, type, notnull, dflt_value, pk
        // Column index 1 is the column name.
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePointer = sqlite3_column_text(statement, 1) {
                names.insert(String(cString: namePointer))
            }
        }

        return names
    }
}

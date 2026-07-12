import SQLite3
import Foundation

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
/// SQLite operations on ≤100 small text rows are sub-millisecond, so there's
/// no need for background threads at this scale.
class ClipboardStore {

    /// The maximum number of clipboard items to retain.
    private let maxItems = 100

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
            print("ClipboardStore: Could not locate Application Support directory.")
            return
        }

        let clippedDir = appSupport.appendingPathComponent("Clipped", isDirectory: true)

        // Create the directory if it doesn't exist. `withIntermediateDirectories`
        // is like `mkdir -p` — it won't fail if the folder is already there.
        do {
            try fileManager.createDirectory(at: clippedDir, withIntermediateDirectories: true)
        } catch {
            print("ClipboardStore: Failed to create directory: \(error)")
            return
        }

        let dbPath = clippedDir.appendingPathComponent("clipped.sqlite").path

        // `sqlite3_open` creates the file if it doesn't exist.
        // It returns SQLITE_OK (0) on success.
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("ClipboardStore: Failed to open database at \(dbPath).")
            return
        }

        createTableIfNeeded()
    }

    /// Closes the database connection when this object is deallocated.
    ///
    /// `deinit` is Swift's destructor — it runs automatically when the
    /// last reference to this object is released. Similar to calling
    /// `dispose()` on a Flutter controller, but you don't call it manually.
    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    /// Loads all clipboard items from the database, newest first.
    func loadAll() -> [ClipboardItem] {
        let sql = "SELECT id, text, copied_at FROM clipboard_items ORDER BY copied_at DESC;"
        var statement: OpaquePointer?

        // `sqlite3_prepare_v2` compiles the SQL string into a prepared
        // statement — like a pre-parsed query the database can execute
        // efficiently.
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("ClipboardStore: Failed to prepare loadAll statement.")
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

            items.append(ClipboardItem(id: id, text: text, copiedAt: copiedAt))
        }

        return items
    }

    /// Inserts a new clipboard text entry and returns the created item.
    ///
    /// Uses parameterized binding (`?` placeholder + `sqlite3_bind_text`)
    /// so that clipboard text containing quotes, SQL, JSON, emoji, or
    /// newlines is handled safely — no SQL injection possible.
    func insert(text: String) -> ClipboardItem? {
        let sql = "INSERT INTO clipboard_items (text, copied_at) VALUES (?, ?);"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("ClipboardStore: Failed to prepare insert statement.")
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
            print("ClipboardStore: Failed to insert item.")
            return nil
        }

        let id = sqlite3_last_insert_rowid(db)
        return ClipboardItem(id: id, text: text, copiedAt: now)
    }

    /// Deletes the oldest items so that at most `maxItems` remain.
    ///
    /// This is the FIFO trim: when the 101st item is added, the oldest
    /// entry is permanently removed from SQLite.
    func trimToLimit() {
        let sql = """
            DELETE FROM clipboard_items
            WHERE id NOT IN (
                SELECT id FROM clipboard_items
                ORDER BY copied_at DESC
                LIMIT ?
            );
            """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("ClipboardStore: Failed to prepare trim statement.")
            return
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(maxItems))

        if sqlite3_step(statement) != SQLITE_DONE {
            print("ClipboardStore: Failed to trim items.")
        }
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
            print("ClipboardStore: Failed to create table.")
        }
    }
}

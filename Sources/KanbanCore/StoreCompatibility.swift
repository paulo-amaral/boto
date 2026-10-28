import Foundation
import SQLite3
import SwiftData

/// Stops an older Boto from opening a database that a newer one has already changed. SwiftData migrates a store to the
/// model it is opened with, and a model that lacks an entity the store has migrates it away: the data in that entity is
/// dropped. So the app and `boto-mcp` look at the entities the store was saved with before they open it, and refuse
/// when the store holds any they do not know.
public enum StoreCompatibility {
    public struct NewerStore: LocalizedError {
        public let entities: [String]
        public var errorDescription: String? {
            "This database holds data from a newer version of Boto (\(entities.joined(separator: ", "))). "
                + "Opening it with this older version would erase that data, so Boto did not. Update Boto and try again."
        }
    }

    /// The database is in use by another process and could not be read in time. The check must not pass on a guess.
    public struct Busy: LocalizedError {
        public var errorDescription: String? { "The Boto database is busy, so Boto could not check it. Close the other Boto window and try again." }
    }

    /// The entities the store was last saved with, or nil when there is no store yet or it is not a Boto database.
    /// Another process that has the store open (the app, while `boto-mcp` starts) can hold a lock for a moment, so a
    /// busy database is waited for, and refused when the wait runs out rather than treated as "nothing to check".
    public static func storedEntities(at url: URL) throws -> Set<String>? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(database) }
        if opened == SQLITE_BUSY || opened == SQLITE_LOCKED { throw Busy() }
        guard opened == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(database, 3000)
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, "select Z_PLIST from Z_METADATA limit 1", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        if prepared == SQLITE_BUSY || prepared == SQLITE_LOCKED { throw Busy() }
        guard prepared == SQLITE_OK else { return nil }
        let stepped = sqlite3_step(statement)
        if stepped == SQLITE_BUSY || stepped == SQLITE_LOCKED { throw Busy() }
        guard stepped == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let hashes = plist["NSStoreModelVersionHashes"] as? [String: Any] else { return nil }
        return Set(hashes.keys)
    }

    /// Throws `NewerStore` when the store has entities this version does not know.
    public static func check(store url: URL, knownEntities: Set<String> = Set(Schema(KanbanSchema.models).entities.map(\.name))) throws {
        guard let stored = try storedEntities(at: url) else { return }
        let unknown = stored.subtracting(knownEntities)
        if !unknown.isEmpty { throw NewerStore(entities: unknown.sorted()) }
    }
}

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

    /// The entities the store was last saved with, or nil when there is no store yet or it cannot be read.
    public static func storedEntities(at url: URL) -> Set<String>? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(database); return nil }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "select Z_PLIST from Z_METADATA limit 1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let hashes = plist["NSStoreModelVersionHashes"] as? [String: Any] else { return nil }
        return Set(hashes.keys)
    }

    /// Throws `NewerStore` when the store has entities this version does not know.
    public static func check(store url: URL, knownEntities: Set<String> = Set(Schema(KanbanSchema.models).entities.map(\.name))) throws {
        guard let stored = storedEntities(at: url) else { return }
        let unknown = stored.subtracting(knownEntities)
        if !unknown.isEmpty { throw NewerStore(entities: unknown.sorted()) }
    }
}

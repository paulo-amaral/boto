import Foundation
import SQLite3

/// Where Boto keeps its files. The folder is readable by the owner only; the store and its backups hold the same data.
public enum BotoPaths {
    public static func supportFolder() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Boto", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return folder
    }

    public static func storeURL() throws -> URL { try supportFolder().appendingPathComponent("Boto.store") }

    public static func backupsFolder() throws -> URL { try supportFolder().appendingPathComponent("Backups", isDirectory: true) }
}

/// One copy of the database per day, keeping the newest few. The copy goes through SQLite's backup API, which reads a
/// consistent snapshot while the app is running and the store is in WAL mode; copying the files could miss recent data.
public enum DatabaseBackup {
    public struct BackupError: LocalizedError {
        let detail: String
        public var errorDescription: String? { detail }
    }

    private static let prefix = "Boto-"
    private static let suffix = ".store"

    static func fileName(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "\(prefix)%04d-%02d-%02d\(suffix)", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func isBackup(_ name: String) -> Bool {
        name.range(of: #"^Boto-\d{4}-\d{2}-\d{2}\.store$"#, options: .regularExpression) != nil
    }

    /// Returns the new copy, or nil when today's copy already exists. Older copies beyond `keep` are deleted;
    /// files in the folder that do not look like Boto backups are never touched.
    @discardableResult
    public static func runDaily(store: URL, folder: URL, keep: Int = 7, now: Date = Date(),
                                calendar: Calendar = .current) throws -> URL? {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let target = folder.appendingPathComponent(fileName(for: now, calendar: calendar))
        guard !fm.fileExists(atPath: target.path) else { return nil }

        // Written under another name and moved into place, so a crash never leaves a half copy looking like a backup.
        let partial = folder.appendingPathComponent(".\(target.lastPathComponent).partial")
        discard(partial)
        do {
            try copyDatabase(from: store, to: partial)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: partial.path)
            // SQLite may have left WAL helper files beside the draft; they must not outlive it.
            discardHelpers(of: partial)
            try fm.moveItem(at: partial, to: target)
        } catch {
            discard(partial)
            throw error
        }
        try prune(folder, keep: keep)
        return target
    }

    private static func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        discardHelpers(of: file)
    }

    private static func discardHelpers(of file: URL) {
        for helper in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path + helper))
        }
    }

    private static func prune(_ folder: URL, keep: Int) throws {
        let fm = FileManager.default
        let backups = try fm.contentsOfDirectory(atPath: folder.path).filter(isBackup).sorted(by: >)
        for name in backups.dropFirst(max(keep, 1)) {
            try fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func copyDatabase(from source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BackupError(detail: "The database file was not found.")
        }
        var from: OpaquePointer?
        var to: OpaquePointer?
        defer { sqlite3_close(from); sqlite3_close(to) }
        guard sqlite3_open_v2(source.path, &from, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw BackupError(detail: "Could not open the database: \(message(from)).")
        }
        guard sqlite3_open_v2(destination.path, &to, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw BackupError(detail: "Could not create the backup file: \(message(to)).")
        }
        guard let backup = sqlite3_backup_init(to, "main", from, "main") else {
            throw BackupError(detail: "Could not start the backup: \(message(to)).")
        }
        let result = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else {
            throw BackupError(detail: "The copy did not finish (SQLite code \(result)).")
        }
        // The copy inherits the store's WAL mode. Leave it as one self-contained file that opens read-only anywhere;
        // the store switches itself back to WAL when it is restored and opened.
        guard sqlite3_exec(to, "PRAGMA journal_mode=DELETE;", nil, nil, nil) == SQLITE_OK else {
            throw BackupError(detail: "Could not finalise the backup file: \(message(to)).")
        }
    }

    private static func message(_ database: OpaquePointer?) -> String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
    }
}

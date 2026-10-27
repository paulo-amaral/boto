import SQLite3
import XCTest
@testable import KanbanCore

final class DatabaseBackupTests: XCTestCase {
    private var root: URL!
    private var store: URL!
    private var folder: URL!
    private var open: OpaquePointer?

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("boto-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = root.appendingPathComponent("Boto.store")
        folder = root.appendingPathComponent("Backups")
    }

    override func tearDownWithError() throws {
        sqlite3_close(open)
        try? FileManager.default.removeItem(at: root)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, sql)
    }

    private func count(in url: URL) -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        sqlite3_prepare_v2(db, "select count(*) from card", -1, &statement, nil)
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : -1
    }

    /// A store in WAL mode with rows that are still only in the -wal file, and a connection left open, as in the app.
    private func makeLiveStore(rows: Int) {
        XCTAssertEqual(sqlite3_open(store.path, &open), SQLITE_OK)
        exec(open, "pragma journal_mode=WAL; pragma wal_autocheckpoint=0; create table card(title text);")
        for index in 0..<rows { exec(open, "insert into card values ('c\(index)');") }
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso + "T12:00:00Z")! }

    func testBackupIncludesRowsThatAreOnlyInTheWAL() throws {
        makeLiveStore(rows: 5)
        let copy = try XCTUnwrap(DatabaseBackup.runDaily(store: store, folder: folder, now: date("2026-10-26"), calendar: calendar))
        XCTAssertEqual(copy.lastPathComponent, "Boto-2026-10-26.store")
        XCTAssertEqual(count(in: copy), 5)
    }

    func testOnlyOneCopyPerDay() throws {
        makeLiveStore(rows: 1)
        XCTAssertNotNil(try DatabaseBackup.runDaily(store: store, folder: folder, now: date("2026-10-26"), calendar: calendar))
        exec(open, "insert into card values ('later');")
        XCTAssertNil(try DatabaseBackup.runDaily(store: store, folder: folder, now: date("2026-10-26"), calendar: calendar))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
        XCTAssertEqual(count(in: folder.appendingPathComponent("Boto-2026-10-26.store")), 1, "the first copy of the day is kept")
    }

    func testKeepsOnlyTheNewestCopiesAndNeverTouchesOtherFiles() throws {
        makeLiveStore(rows: 1)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "mine".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        for day in 20...26 {
            try DatabaseBackup.runDaily(store: store, folder: folder, keep: 3, now: date("2026-10-\(day)"), calendar: calendar)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["Boto-2026-10-24.store", "Boto-2026-10-25.store", "Boto-2026-10-26.store", "notes.txt"])
    }

    func testBackupsAreOwnerOnly() throws {
        makeLiveStore(rows: 1)
        let copy = try XCTUnwrap(DatabaseBackup.runDaily(store: store, folder: folder, now: date("2026-10-26"), calendar: calendar))
        let folderMode = try FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? Int
        let fileMode = try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int
        XCTAssertEqual(folderMode, 0o700)
        XCTAssertEqual(fileMode, 0o600)
    }

    func testMissingStoreThrowsAndLeavesNothingBehind() throws {
        XCTAssertThrowsError(try DatabaseBackup.runDaily(store: store, folder: folder, now: date("2026-10-26"), calendar: calendar))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "no half-written copy")
    }

    func testFileNameUsesTheLocalCalendarDay() {
        XCTAssertEqual(DatabaseBackup.fileName(for: date("2026-01-05"), calendar: calendar), "Boto-2026-01-05.store")
    }
}

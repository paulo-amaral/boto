import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class StoreCompatibilityTests: XCTestCase {
    private var folder: URL?

    private func makeStore() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("boto-compat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Boto.store")
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(url: url))
        container.mainContext.insert(Project(name: "P"))
        try container.mainContext.save()
        return url
    }

    private var current: Set<String> { Set(Schema(KanbanSchema.models).entities.map(\.name)) }

    func testAStoreFromThisVersionOpens() throws {
        let url = try makeStore()
        XCTAssertNoThrow(try StoreCompatibility.check(store: url))
        XCTAssertTrue(try XCTUnwrap(StoreCompatibility.storedEntities(at: url)).contains("Note"))
    }

    func testAStoreWithAnEntityThisVersionLacksIsRefused() throws {
        let url = try makeStore()
        let older = current.subtracting(["Note"])
        XCTAssertThrowsError(try StoreCompatibility.check(store: url, knownEntities: older)) { error in
            XCTAssertEqual((error as? StoreCompatibility.NewerStore)?.entities, ["Note"])
            XCTAssertTrue(error.localizedDescription.contains("newer version of Boto"))
        }
    }

    func testRefusingLeavesTheStoreUntouched() throws {
        let url = try makeStore()
        let before = try Data(contentsOf: url)
        _ = try? StoreCompatibility.check(store: url, knownEntities: current.subtracting(["Note"]))
        XCTAssertEqual(try Data(contentsOf: url), before, "the check only reads")
    }

    func testANewerVersionMayHaveFewerEntitiesThanTheStore() throws {
        // A store from an older version has fewer entities than the app knows, which is the normal upgrade.
        let url = try makeStore()
        XCTAssertNoThrow(try StoreCompatibility.check(store: url, knownEntities: current.union(["Something"])))
    }

    func testNoStoreAndAnUnreadableFileAreNotAnError() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).store")
        XCTAssertNil(StoreCompatibility.storedEntities(at: missing))
        XCTAssertNoThrow(try StoreCompatibility.check(store: missing))
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID().uuidString).store")
        try Data("not a database".utf8).write(to: junk)
        addTeardownBlock { try? FileManager.default.removeItem(at: junk) }
        XCTAssertNil(StoreCompatibility.storedEntities(at: junk))
        XCTAssertNoThrow(try StoreCompatibility.check(store: junk))
    }
}

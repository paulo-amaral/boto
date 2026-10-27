import Foundation
import SwiftData
import XCTest
@testable import BotoMCP
@testable import KanbanCore

@MainActor
final class MCPServerTests: XCTestCase {
    private var container: ModelContainer?
    private var nextId = 1

    private func makeServer(readOnly: Bool = false) throws -> (MCPServer, Project, Board, BoardList) {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let project = Project(name: "Client")
        container.mainContext.insert(project)
        let board = project.addBoard(name: "Roadmap")
        let list = board.orderedLists[0]
        try container.mainContext.save()
        return (MCPServer(context: container.mainContext, readOnly: readOnly), project, board, list)
    }

    private func send(_ server: MCPServer, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        nextId += 1
        let request: [String: Any] = ["jsonrpc": "2.0", "id": nextId, "method": method, "params": params]
        let line = String(data: try JSONSerialization.data(withJSONObject: request), encoding: .utf8) ?? ""
        let reply = try XCTUnwrap(server.handle(line: line))
        XCTAssertFalse(reply.contains("\n"), "stdio messages must not contain newlines")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    /// Calls a tool and returns whether it failed and the JSON the tool printed.
    private func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) throws -> (isError: Bool, json: [String: Any], text: String) {
        let reply = try send(server, "tools/call", ["name": name, "arguments": arguments])
        let result = try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
        let text = try XCTUnwrap(((result["content"] as? [[String: Any]])?.first)?["text"] as? String)
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
        return (result["isError"] as? Bool ?? false, json, text)
    }

    func testInitializeEchoesASupportedVersionAndOffersTools() throws {
        let (server, _, _, _) = try makeServer()
        let reply = try send(server, "initialize", ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "t", "version": "1"]])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "boto")
    }

    func testAnUnsupportedVersionGetsTheLatestOne() throws {
        let (server, _, _, _) = try makeServer()
        let reply = try send(server, "initialize", ["protocolVersion": "1.0.0"])
        XCTAssertEqual((reply["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServer.latestVersion)
    }

    func testNotificationsAndClientRepliesGetNoAnswer() throws {
        let (server, _, _, _) = try makeServer()
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"no/such/thing"}"#), "a notification is never answered")
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","id":1,"result":{}}"#))
    }

    func testProtocolErrors() throws {
        let (server, _, _, _) = try makeServer()
        let parse = try XCTUnwrap(server.handle(line: "{not json"))
        XCTAssertTrue(parse.contains("-32700"))
        let unknown = try send(server, "no/such/method")
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let tool = try send(server, "tools/call", ["name": "drop_database", "arguments": [String: Any]()])
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertTrue(try XCTUnwrap(server.handle(line: "[1]")).contains("-32600"), "batches are not part of this protocol version")
    }

    func testPingAndToolsList() throws {
        let (server, _, _, _) = try makeServer()
        XCTAssertNotNil(try send(server, "ping")["result"])
        let tools = try XCTUnwrap((try send(server, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("create_card") && names.contains("get_board"))
        XCTAssertFalse(names.contains { $0.contains("delete") }, "nothing here deletes")
        for tool in tools {
            XCTAssertEqual((tool["inputSchema"] as? [String: Any])?["type"] as? String, "object")
        }
    }

    func testReadOnlyHidesAndRefusesEveryWrite() throws {
        let (server, _, _, list) = try makeServer(readOnly: true)
        let names = try XCTUnwrap((try send(server, "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]]).compactMap { $0["name"] as? String }
        XCTAssertEqual(Set(names), ["list_projects", "get_board", "get_card", "get_card_activity", "list_labels", "search", "get_time_report"], "duplicate_project is a write tool")
        let reply = try send(server, "tools/call", ["name": "create_card", "arguments": ["list_id": list.publicId, "title": "x"]])
        XCTAssertNotNil(reply["error"], "a write tool does not exist in read-only mode")
        XCTAssertTrue(list.orderedCards.isEmpty)
    }

    func testListProjectsShowsBoardsAndListsWithIds() throws {
        let (server, project, board, list) = try makeServer()
        list.addCard(title: "A")
        let result = try call(server, "list_projects")
        let projects = try XCTUnwrap(result.json["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.first?["id"] as? String, project.publicId)
        let boards = try XCTUnwrap(projects.first?["boards"] as? [[String: Any]])
        XCTAssertEqual(boards.first?["id"] as? String, board.publicId)
        let lists = try XCTUnwrap(boards.first?["lists"] as? [[String: Any]])
        XCTAssertEqual(lists.first?["cards"] as? Int, 1)
    }

    func testCreateUpdateMoveAndReadACard() throws {
        let (server, _, board, list) = try makeServer()
        let doing = board.orderedLists[1]
        let created = try call(server, "create_card", ["list_id": list.publicId, "title": "  Draft the brief  ", "description": "Two pages", "due_date": "2026-11-02", "importance": "high"])
        XCTAssertFalse(created.isError, created.text)
        let id = try XCTUnwrap(created.json["id"] as? String)
        XCTAssertEqual(created.json["title"] as? String, "Draft the brief")
        XCTAssertEqual(created.json["due_date"] as? String, "2026-11-02")

        let updated = try call(server, "update_card", ["card_id": id, "title": "Draft the brief v2", "due_date": NSNull(), "importance": "low"])
        XCTAssertFalse(updated.isError, updated.text)
        XCTAssertNil(updated.json["due_date"], "null clears the date")
        XCTAssertEqual(updated.json["importance"] as? String, "low")

        let moved = try call(server, "move_card", ["card_id": id, "list_id": doing.publicId, "position": 0])
        XCTAssertFalse(moved.isError, moved.text)
        XCTAssertEqual(moved.json["list"] as? String, doing.name)
        XCTAssertEqual(doing.orderedCards.map(\.title), ["Draft the brief v2"])

        let card = try call(server, "get_card", ["card_id": id])
        XCTAssertEqual(card.json["description"] as? String, "Two pages")
        let recent = try XCTUnwrap(card.json["recent_activity"] as? [[String: Any]])
        XCTAssertFalse(recent.isEmpty)
    }

    func testBadArgumentsAreToolErrorsAndChangeNothing() throws {
        let (server, _, _, list) = try makeServer()
        let card = list.addCard(title: "Keep me")
        XCTAssertTrue(try call(server, "create_card", ["list_id": list.publicId, "title": "   "]).isError)
        XCTAssertTrue(try call(server, "create_card", ["list_id": "nope", "title": "x"]).isError)
        XCTAssertTrue(try call(server, "create_card", ["list_id": list.publicId, "title": String(repeating: "x", count: 501)]).isError)
        XCTAssertTrue(try call(server, "create_card", ["list_id": list.publicId, "title": "x", "due_date": "2026-13-45"]).isError)
        XCTAssertTrue(try call(server, "create_card", ["list_id": list.publicId, "title": "x", "importance": "urgent"]).isError)
        let half = try call(server, "update_card", ["card_id": card.publicId, "title": "Changed", "due_date": "not a date"])
        XCTAssertTrue(half.isError)
        XCTAssertEqual(card.title, "Keep me", "an invalid argument must not apply the valid ones")
        XCTAssertEqual(list.orderedCards.count, 1)
        XCTAssertTrue(try call(server, "move_card", ["card_id": card.publicId, "list_id": list.publicId, "position": 9]).isError)
    }

    func testChecklistItemsAreCreatedAndTicked() throws {
        let (server, _, _, list) = try makeServer()
        let card = list.addCard(title: "A")
        let first = try call(server, "add_checklist_item", ["card_id": card.publicId, "title": "Export the ledger"])
        XCTAssertEqual(first.json["checklist"] as? String, "Checklist")
        _ = try call(server, "add_checklist_item", ["card_id": card.publicId, "title": "Compare quarters"])
        XCTAssertEqual(card.checklists.count, 1, "the second item joins the first checklist")
        let named = try call(server, "add_checklist_item", ["card_id": card.publicId, "title": "Send", "checklist": "Delivery"])
        XCTAssertEqual(named.json["checklist"] as? String, "Delivery")

        let itemId = try XCTUnwrap(first.json["item_id"] as? String)
        XCTAssertFalse(try call(server, "set_checklist_item_completed", ["item_id": itemId, "completed": true]).isError)
        XCTAssertEqual(card.checklistProgress.done, 1)
        XCTAssertEqual(card.checklistProgress.total, 3)
    }

    func testTimeIsLoggedAndReported() throws {
        let (server, project, _, list) = try makeServer()
        let card = list.addCard(title: "A")
        XCTAssertFalse(try call(server, "log_time", ["card_id": card.publicId, "minutes": 90, "date": "2026-10-26", "note": "Ledger"]).isError)
        XCTAssertFalse(try call(server, "log_time", ["project_id": project.publicId, "minutes": 30, "date": "2026-10-26"]).isError)
        XCTAssertTrue(try call(server, "log_time", ["card_id": card.publicId, "minutes": 0]).isError)
        XCTAssertTrue(try call(server, "log_time", ["card_id": card.publicId, "minutes": 1441]).isError)
        XCTAssertTrue(try call(server, "log_time", ["minutes": 10]).isError, "needs a card or a project")
        XCTAssertTrue(try call(server, "log_time", ["card_id": card.publicId, "project_id": project.publicId, "minutes": 10]).isError)

        let report = try call(server, "get_time_report", ["project_id": project.publicId, "from": "2026-10-26", "to": "2026-10-27"])
        XCTAssertEqual(report.json["total"] as? String, "2:00")
        XCTAssertEqual(report.json["total_seconds"] as? Int, 7200)
    }

    func testActivityListsCommentsAndCanFilterToThem() throws {
        let (server, _, _, list) = try makeServer()
        let card = list.addCard(title: "A")
        card.addComment("Waiting on the client")
        card.setImportance(.high)
        let all = try XCTUnwrap(try call(server, "get_card_activity", ["card_id": card.publicId]).json["activity"] as? [[String: Any]])
        XCTAssertTrue(all.contains { $0["kind"] as? String == "created" })
        XCTAssertTrue(all.contains { $0["kind"] as? String == "importanceChanged" })
        let comments = try XCTUnwrap(try call(server, "get_card_activity", ["card_id": card.publicId, "comments_only": true]).json["activity"] as? [[String: Any]])
        XCTAssertEqual(comments.map { $0["text"] as? String }, ["Waiting on the client"])
        let limited = try XCTUnwrap(try call(server, "get_card_activity", ["card_id": card.publicId, "limit": 1]).json["activity"] as? [[String: Any]])
        XCTAssertEqual(limited.count, 1, "the latest entry only")
        XCTAssertTrue(try call(server, "get_card_activity", ["card_id": "nope"]).isError)
    }

    func testLabelsShowColourAndOpenCardCounts() throws {
        let (server, _, board, list) = try makeServer()
        let label = KanbanCore.Label(name: "Research", colourCode: "#3b82f6")
        board.labels.append(label)
        let open = list.addCard(title: "Open"); open.attach(label)
        let archived = list.addCard(title: "Archived"); archived.attach(label); archived.setArchived(true)
        let labels = try XCTUnwrap(try call(server, "list_labels", ["board_id": board.publicId]).json["labels"] as? [[String: Any]])
        XCTAssertEqual(labels.first?["name"] as? String, "Research")
        XCTAssertEqual(labels.first?["colour"] as? String, "#3b82f6")
        XCTAssertEqual(labels.first?["open_cards"] as? Int, 1, "archived cards are not counted")
        XCTAssertTrue(try call(server, "list_labels", ["board_id": "nope"]).isError)
    }

    func testDuplicateProjectCopiesWithOrWithoutCards() throws {
        let (server, project, board, list) = try makeServer()
        list.addCard(title: "Kickoff")
        board.labels.append(KanbanCore.Label(name: "Research"))

        let full = try call(server, "duplicate_project", ["project_id": project.publicId])
        XCTAssertFalse(full.isError, full.text)
        XCTAssertEqual(full.json["name"] as? String, "Client copy")
        let fullLists = try XCTUnwrap(((full.json["boards"] as? [[String: Any]])?.first?["lists"]) as? [[String: Any]])
        XCTAssertEqual(fullLists.first?["cards"] as? Int, 1)

        let template = try call(server, "duplicate_project", ["project_id": project.publicId, "name": "  Template  ", "structure_only": true])
        XCTAssertEqual(template.json["name"] as? String, "Template")
        let templateLists = try XCTUnwrap(((template.json["boards"] as? [[String: Any]])?.first?["lists"]) as? [[String: Any]])
        XCTAssertEqual(templateLists.map { $0["cards"] as? Int }, [0, 0, 0])

        let again = try call(server, "duplicate_project", ["project_id": project.publicId])
        XCTAssertEqual(again.json["name"] as? String, "Client copy 2", "a copy never takes a name in use")
        XCTAssertEqual(list.orderedCards.count, 1, "the original is untouched")
        XCTAssertTrue(try call(server, "duplicate_project", ["project_id": "nope"]).isError)
    }

    func testSearchFindsCardsAcrossProjects() throws {
        let (server, _, _, list) = try makeServer()
        list.addCard(title: "Vendor shortlist")
        let found = try XCTUnwrap(try call(server, "search", ["query": "vendor"]).json["results"] as? [[String: Any]])
        XCTAssertEqual(found.first?["title"] as? String, "Vendor shortlist")
        XCTAssertTrue(try XCTUnwrap(try call(server, "search", ["query": "zzz"]).json["results"] as? [Any]).isEmpty)
    }

    func testACardOnTheCalendarCannotBeCompletedOrArchivedFromHere() throws {
        let (server, _, _, list) = try makeServer()
        let card = list.addCard(title: "Has an event")
        card.calendarEventID = "event-1"
        XCTAssertTrue(try call(server, "update_card", ["card_id": card.publicId, "completed": true]).isError)
        XCTAssertTrue(try call(server, "set_card_archived", ["card_id": card.publicId, "archived": true]).isError)
        XCTAssertFalse(card.isCompleted)
        XCTAssertFalse(card.isArchived)
        XCTAssertFalse(try call(server, "update_card", ["card_id": card.publicId, "title": "Renamed"]).isError, "other edits are fine")
    }

    func testDeletedThingsAreInvisibleToTheTools() throws {
        let (server, _, _, list) = try makeServer()
        let card = list.addCard(title: "Gone")
        card.deletedAt = Date()
        XCTAssertTrue(try call(server, "get_card", ["card_id": card.publicId]).isError)
        XCTAssertTrue(try call(server, "update_card", ["card_id": card.publicId, "title": "x"]).isError)
    }
}

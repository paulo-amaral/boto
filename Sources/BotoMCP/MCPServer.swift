import Foundation
import KanbanCore
import SwiftData

/// A Model Context Protocol server over the stdio transport: one JSON-RPC message per line, no embedded newlines,
/// and nothing but messages on stdout (specification 2025-06-18). Only the tools capability is offered.
@MainActor
public final class MCPServer {
    public static let latestVersion = "2025-06-18"
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let tools: BotoTools

    public init(context: ModelContext, readOnly: Bool = false) {
        tools = BotoTools(context: context, readOnly: readOnly)
    }

    /// The reply to one incoming line, or nil when none is due (notifications, and replies from the client).
    public func handle(line: String) -> String? {
        guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else {
            return error(id: NSNull(), code: -32700, "Parse error")
        }
        guard let message = object as? [String: Any] else { return error(id: NSNull(), code: -32600, "Invalid Request") }
        guard let method = message["method"] as? String else {
            return message["result"] != nil || message["error"] != nil ? nil : error(id: message["id"] ?? NSNull(), code: -32600, "Invalid Request")
        }
        // No id means a notification: it is never answered, even when the method is unknown.
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            return result(id: id, [
                "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.latestVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "boto", "version": "0.2.0"],
                "instructions": "Boto is a personal Kanban app. Ids come from list_projects, get_board and search. "
                    + "Nothing is ever deleted through these tools; restore and delete happen in the app. "
                    + "When started without --allow-writes the server only reads, and the write tools are not listed.",
            ])
        case "ping":
            return result(id: id, [String: Any]())
        case "tools/list":
            return result(id: id, ["tools": tools.definitions.map(\.json)])
        case "tools/call":
            guard let name = params["name"] as? String, tools.knows(name) else {
                return error(id: id, code: -32602, "Unknown tool: \(params["name"] as? String ?? "")")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                return result(id: id, content(try tools.call(name, arguments), isError: false))
            } catch let failure as ToolError {
                return result(id: id, content(failure.message, isError: true))
            } catch {
                return result(id: id, content("The tool failed: \(error.localizedDescription)", isError: true))
            }
        default:
            return error(id: id, code: -32601, "Method not found: \(method)")
        }
    }

    private func content(_ value: Any, isError: Bool) -> [String: Any] {
        let text = (value as? String) ?? Self.encode(value) ?? "{}"
        return ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func result(id: Any, _ result: [String: Any]) -> String? {
        Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func error(id: Any, code: Int, _ message: String) -> String? {
        Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    /// Compact output has no newlines, which the transport requires.
    static func encode(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

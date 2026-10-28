import BotoMCP
import Foundation
import KanbanCore
import SwiftData

// Boto's MCP server, for an AI assistant to read and update the same database the app uses.
// Usage: boto-mcp [--allow-writes]   (talks JSON-RPC over stdin and stdout; logs go to stderr)
// Read-only unless --allow-writes is given: changing the database is something the person turns on.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("boto-mcp: \(message)\n".utf8))
    exit(1)
}

@MainActor
func serve() {
    let container: ModelContainer
    do {
        try StoreCompatibility.check(store: try BotoPaths.storeURL())
        container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(url: try BotoPaths.storeURL()))
    } catch {
        fail("could not open the Boto database: \(error)")
    }

    let server = MCPServer(context: container.mainContext, readOnly: !CommandLine.arguments.contains("--allow-writes"))
    while let line = readLine(strippingNewline: true) {
        guard !line.isEmpty, let reply = server.handle(line: line) else { continue }
        FileHandle.standardOutput.write(Data((reply + "\n").utf8))
    }
}

MainActor.assumeIsolated { serve() }

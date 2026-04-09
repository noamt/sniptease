import Foundation

// MARK: - MCP Server
//
// Minimal MCP (Model Context Protocol) server over stdio.
// Implements JSON-RPC 2.0 with MCP lifecycle:
//   initialize → initialized → tools/list → tools/call
//
// Launch SnipTease with `--mcp` to start in headless server mode.

@MainActor
final class MCPServer {

    private let tools: MCPTools
    private var isRunning = true

    init(tools: MCPTools) {
        self.tools = tools
    }

    // MARK: - Run Loop

    func run() async {
        // Unbuffer stdout so agents see responses immediately
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        log("SnipTease MCP server starting...")

        while isRunning {
            guard let line = readLine(strippingNewline: true) else {
                // stdin closed — agent disconnected
                log("stdin closed, shutting down")
                break
            }

            if line.isEmpty { continue }

            do {
                let response = try await handleMessage(line)
                if let response {
                    write(response)
                }
            } catch {
                log("Error handling message: \(error)")
                if let id = extractID(from: line) {
                    write(errorResponse(id: id, code: -32603, message: error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ raw: String) async throws -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else {
            throw MCPError.invalidRequest("Malformed JSON-RPC message")
        }

        let id = json["id"]  // nil for notifications
        let params = json["params"] as? [String: Any] ?? [:]

        switch method {

        // ── Lifecycle ────────────────────────────────────────
        case "initialize":
            return jsonRPC(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": ["listChanged": false]
                ],
                "serverInfo": [
                    "name": "sniptease",
                    "version": "1.0.0"
                ]
            ])

        case "notifications/initialized":
            log("Agent connected ✓")
            return nil  // notification, no response

        // ── Tool Discovery ───────────────────────────────────
        case "tools/list":
            return jsonRPC(id: id, result: [
                "tools": tools.listTools()
            ])

        // ── Tool Execution ───────────────────────────────────
        case "tools/call":
            guard let name = params["name"] as? String else {
                throw MCPError.invalidRequest("Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = try await tools.callTool(name: name, arguments: arguments)
            return jsonRPC(id: id, result: [
                "content": result
            ])

        // ── Unknown ──────────────────────────────────────────
        default:
            if id != nil {
                throw MCPError.methodNotFound(method)
            }
            return nil  // unknown notification, ignore
        }
    }

    // MARK: - JSON-RPC Helpers

    private func jsonRPC(id: Any?, result: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        response["id"] = id ?? NSNull()
        return response
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        response["id"] = id ?? NSNull()
        return response
    }

    private func extractID(from raw: String) -> Any? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["id"]
    }

    // MARK: - I/O

    private func write(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return
        }
        print(str)  // stdout, one JSON object per line
        fflush(stdout)
    }

    func log(_ message: String) {
        FileHandle.standardError.write(Data("[sniptease-mcp] \(message)\n".utf8))
    }
}

// MARK: - Errors

enum MCPError: LocalizedError {
    case invalidRequest(String)
    case methodNotFound(String)
    case toolNotFound(String)
    case toolFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .methodNotFound(let m): return "Method not found: \(m)"
        case .toolNotFound(let t): return "Unknown tool: \(t)"
        case .toolFailed(let msg): return "Tool failed: \(msg)"
        }
    }
}

import Foundation

enum AgentLoopDecision {
    case tool(AgentToolCall)
    case final(String)
}

enum AgentLoop {
    static let maximumIterations = 6
    static let maximumToolCallsPerTurn = 3
    static let requestTimeout: TimeInterval = 60
    static let toolTimeout: TimeInterval = 30
    static let maximumRetries = 2

    static func decision(from response: String) -> AgentLoopDecision {
        guard let object = jsonObject(in: response) else { return .final(response) }
        if let type = object["type"] as? String, type == "final" {
            return .final((object["text"] as? String) ?? "")
        }
        if let type = object["type"] as? String, type == "tool_call",
           let name = object["name"] as? String,
           let call = AgentToolCall(jsonName: name, rawArguments: object["arguments"] ?? [:]) {
            return .tool(call)
        }
        return .final(response)
    }

    static func appendToolResult(_ result: AgentToolResult, toolName: String, to context: String) -> String {
        let capped = String(result.message.prefix(1600))
        let record = "Tool result (\(toolName), success=\(result.succeeded)): \(capped)"
        return String((context.isEmpty ? record : context + "\n\n" + record).suffix(6000))
    }

    private static func jsonObject(in response: String) -> [String: Any]? {
        var candidate = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fence = candidate.range(of: "```json", options: [.caseInsensitive]) {
            candidate = String(candidate[fence.upperBound...])
            if let closing = candidate.range(of: "```") { candidate = String(candidate[..<closing.lowerBound]) }
        } else if let first = candidate.firstIndex(of: "{"), let last = candidate.lastIndex(of: "}"), first < last {
            candidate = String(candidate[first...last])
        }
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

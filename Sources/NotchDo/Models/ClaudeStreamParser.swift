import Foundation

/// Turns single stream-json lines into `ClaudeEvent`s. Unknown or malformed lines yield
/// nothing; they are still kept verbatim in the task's event log.
enum ClaudeStreamParser {
    static func parse(line: String) -> [ClaudeEvent] {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return [] }
            return [.started(
                sessionID: object["session_id"] as? String,
                model: object["model"] as? String
            )]
        case "assistant":
            return blocks(in: object).compactMap(assistantEvent)
        case "user":
            return blocks(in: object).compactMap(userEvent)
        case "result":
            return [.result(ClaudeResult(
                text: (object["result"] as? String) ?? "",
                isError: (object["is_error"] as? Bool) ?? false,
                turns: (object["num_turns"] as? Int) ?? 0,
                costUSD: object["total_cost_usd"] as? Double
            ))]
        default:
            return []
        }
    }

    /// The first claude.ai Artifact link in `text`, if any.
    static func artifactURL(in text: String) -> URL? {
        guard let range = text.range(
            of: #"https://claude\.ai/(?:code/)?artifact/[A-Za-z0-9_-]+"#,
            options: .regularExpression
        ) else { return nil }
        return URL(string: String(text[range]))
    }

    private static func blocks(in object: [String: Any]) -> [[String: Any]] {
        let message = object["message"] as? [String: Any]
        return (message?["content"] as? [[String: Any]]) ?? []
    }

    private static func assistantEvent(_ block: [String: Any]) -> ClaudeEvent? {
        switch block["type"] as? String {
        case "text":
            guard let text = block["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .assistantText(text)
        case "tool_use":
            guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            let input = block["input"] as? [String: Any] ?? [:]
            let publishes = name == "Artifact" && ((input["action"] as? String) ?? "publish") == "publish"
            return .toolUse(
                id: id,
                name: name,
                detail: detail(for: name, input: input),
                publishesArtifact: publishes
            )
        default:
            return nil
        }
    }

    private static func userEvent(_ block: [String: Any]) -> ClaudeEvent? {
        guard block["type"] as? String == "tool_result",
              let id = block["tool_use_id"] as? String else { return nil }
        if let text = block["content"] as? String {
            return .toolResult(id: id, text: text)
        }
        if let parts = block["content"] as? [[String: Any]] {
            return .toolResult(id: id, text: parts.compactMap { $0["text"] as? String }.joined(separator: "\n"))
        }
        return .toolResult(id: id, text: "")
    }

    /// A short, human-readable target for the activity line, e.g. a path or command.
    private static func detail(for name: String, input: [String: Any]) -> String? {
        for key in ["file_path", "path", "command", "pattern", "url", "query", "description", "action"] {
            if let value = input[key] as? String, !value.isEmpty {
                let oneLine = value.split(whereSeparator: \.isNewline).first.map(String.init) ?? value
                return oneLine.count > 80 ? String(oneLine.prefix(79)) + "…" : oneLine
            }
        }
        return nil
    }
}

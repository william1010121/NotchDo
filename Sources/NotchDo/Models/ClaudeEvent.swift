/// What NotchDo understands from one line of `claude -p --output-format stream-json`.
enum ClaudeEvent: Equatable, Sendable {
    case started(sessionID: String?, model: String?)
    case assistantText(String)
    case toolUse(id: String, name: String, detail: String?, publishesArtifact: Bool)
    case toolResult(id: String, text: String)
    case result(ClaudeResult)
}

struct ClaudeResult: Equatable, Sendable {
    var text: String
    var isError: Bool
    var turns: Int
    var costUSD: Double?
}

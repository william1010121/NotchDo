import Foundation

/// Everything needed to start one `claude -p` process. The prompt goes to stdin, which
/// avoids argument-length limits and shell quoting.
struct ClaudeRunRequest: Equatable, Sendable {
    var executable: URL
    var workingDirectory: URL
    var sessionID: UUID
    var resume: Bool
    var prompt: String
    var permissionMode: AIPermissionMode
    var allowedTools: [String]
    var appendSystemPrompt: String

    var arguments: [String] {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            resume ? "--resume" : "--session-id", sessionID.uuidString.lowercased(),
            "--permission-mode", permissionMode.rawValue
        ]
        // bypassPermissions already allows everything; plan mode must stay read-only.
        if permissionMode == .acceptEdits, !allowedTools.isEmpty {
            arguments += ["--allowedTools", allowedTools.joined(separator: ",")]
        }
        if !appendSystemPrompt.isEmpty {
            arguments += ["--append-system-prompt", appendSystemPrompt]
        }
        return arguments
    }
}

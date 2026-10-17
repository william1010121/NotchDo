import Foundation

/// Snapshot of the user's AI preferences, read when a task starts.
struct AISettings: Equatable, Sendable {
    static let maxConcurrentRange = 1...3
    static let defaultPort = 47821
    static let defaultAllowedTools = [
        "Read", "Edit", "Write", "Glob", "Grep", "WebFetch", "WebSearch",
        "Bash(git:*)", "Bash(swift:*)", "Bash(npm:*)", "Bash(node:*)",
        "Bash(python3:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(mkdir:*)"
    ]

    var permissionMode: AIPermissionMode = .acceptEdits
    var maxConcurrent = 1
    var publishArtifacts = true
    var notifyOnFinish = true
    var serverEnabled = true
    var serverPort = AISettings.defaultPort
    var claudePathOverride = ""

    /// Tools passed to `--allowedTools`, including Artifact only when publishing is on.
    var allowedTools: [String] {
        Self.defaultAllowedTools + (publishArtifacts ? ["Artifact"] : [])
    }
}

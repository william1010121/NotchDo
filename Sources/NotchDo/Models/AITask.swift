import Foundation

/// A todo delegated to Claude. Persisted as `.notchdo/tasks/<id>/task.json` in the AI workspace.
/// Independent of Apple Reminders: never mirrored into EventKit.
struct AITask: Codable, Identifiable, Equatable, Sendable {
    static let maxTitleLength = 80

    let id: UUID
    var title: String
    var prompt: String
    var status: AITaskStatus
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var summary: String?
    var lastActivity: String?
    var errorMessage: String?
    var artifactURLs: [URL] = []
    var turnCount: Int = 0
    var costUSD: Double?
    /// The Claude session for this task. A retry gets a fresh one; a follow-up resumes it.
    var sessionID: UUID?
    /// Follow-up prompts already sent, oldest first.
    var followUps: [String] = []
    /// A follow-up waiting to run on the existing session.
    var pendingPrompt: String?

    init(
        id: UUID = UUID(),
        prompt: String,
        status: AITaskStatus = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.title = Self.makeTitle(from: prompt)
        self.status = status
        self.createdAt = createdAt
    }

    // Newer fields are decoded leniently so task files written by earlier builds still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        prompt = try c.decode(String.self, forKey: .prompt)
        status = try c.decode(AITaskStatus.self, forKey: .status)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        lastActivity = try c.decodeIfPresent(String.self, forKey: .lastActivity)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        artifactURLs = try c.decodeIfPresent([URL].self, forKey: .artifactURLs) ?? []
        turnCount = try c.decodeIfPresent(Int.self, forKey: .turnCount) ?? 0
        costUSD = try c.decodeIfPresent(Double.self, forKey: .costUSD)
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
        followUps = try c.decodeIfPresent([String].self, forKey: .followUps) ?? []
        pendingPrompt = try c.decodeIfPresent(String.self, forKey: .pendingPrompt)
    }

    /// First non-empty line of the prompt, trimmed and limited to `maxTitleLength` characters.
    static func makeTitle(from prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        guard firstLine.count > maxTitleLength else { return firstLine }
        return String(firstLine.prefix(maxTitleLength - 1)) + "…"
    }
}

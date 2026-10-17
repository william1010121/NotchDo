import Foundation

/// Storage seam for AI tasks so the store can be tested without touching the real workspace.
protocol AITaskPersisting: Sendable {
    /// Every readable task. Unreadable task folders are skipped.
    func loadAll() throws -> [AITask]
    func save(_ task: AITask) throws
    /// Appends one raw stream-json line to the task's `events.jsonl`.
    func appendEventLine(_ line: String, for id: UUID) throws
    /// Raw event lines after the first `offset` lines.
    func eventLines(for id: UUID, after offset: Int) throws -> [String]
    func writeResult(_ text: String, for id: UUID) throws
    func result(for id: UUID) -> String?
    /// Removes a task's whole folder.
    func delete(_ id: UUID) throws
    /// Clears the event log and result before a retry.
    func resetRunFiles(for id: UUID) throws
}

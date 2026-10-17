import Foundation
@testable import NotchDo

/// In-memory `AITaskPersisting` that can be told to fail.
final class FakeAITaskPersistence: AITaskPersisting, @unchecked Sendable {
    struct Failure: Error {}

    private let lock = NSLock()
    private var stored: [AITask]
    private var failsSaving = false
    private var failsLoading = false
    private var saved: [AITask] = []
    private var events: [UUID: [String]] = [:]
    private var results: [UUID: String] = [:]

    init(tasks: [AITask] = []) {
        stored = tasks
    }

    var savedTasks: [AITask] { lock.withLock { saved } }

    func setFailsSaving(_ value: Bool) { lock.withLock { failsSaving = value } }
    func setFailsLoading(_ value: Bool) { lock.withLock { failsLoading = value } }

    func loadAll() throws -> [AITask] {
        try lock.withLock {
            if failsLoading { throw Failure() }
            return stored
        }
    }

    func save(_ task: AITask) throws {
        try lock.withLock {
            if failsSaving { throw Failure() }
            saved.append(task)
            stored.removeAll { $0.id == task.id }
            stored.append(task)
        }
    }

    func appendEventLine(_ line: String, for id: UUID) throws {
        lock.withLock { events[id, default: []].append(line) }
    }

    func eventLines(for id: UUID, after offset: Int) throws -> [String] {
        lock.withLock { Array((events[id] ?? []).dropFirst(offset)) }
    }

    func writeResult(_ text: String, for id: UUID) throws {
        lock.withLock { results[id] = text }
    }

    func result(for id: UUID) -> String? {
        lock.withLock { results[id] }
    }

    private var deleted: [UUID] = []
    var deletedIDs: [UUID] { lock.withLock { deleted } }
    private var failsDeleting = false
    func setFailsDeleting(_ value: Bool) { lock.withLock { failsDeleting = value } }

    func delete(_ id: UUID) throws {
        try lock.withLock {
            if failsDeleting { throw Failure() }
            deleted.append(id)
            stored.removeAll { $0.id == id }
        }
    }

    func resetRunFiles(for id: UUID) throws {
        lock.withLock {
            events[id] = nil
            results[id] = nil
        }
    }
}

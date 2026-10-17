import Foundation
import Observation

enum AITaskStoreError: LocalizedError, Equatable {
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .emptyPrompt: "Describe what you want Claude to do."
        }
    }
}

/// Single source of truth for AI tasks, shared by the capture panel, the notch UI,
/// and (later) the local progress server.
@MainActor
@Observable
final class AITaskStore {
    private(set) var tasks: [AITask] = []
    private(set) var loadErrorMessage: String?
    /// Called after a new task is saved, so the scheduler can start it.
    var onTaskAdded: ((AITask) -> Void)?

    private let persistence: any AITaskPersisting
    private let now: () -> Date

    init(persistence: any AITaskPersisting, now: @escaping () -> Date = Date.init) {
        self.persistence = persistence
        self.now = now
    }

    /// Loads saved tasks. A task still marked `running` means the app quit mid-run, so it
    /// is closed out as failed rather than shown as active forever.
    func load() {
        do {
            var loaded = try persistence.loadAll()
            for index in loaded.indices where loaded[index].status == .running {
                loaded[index].status = .failed
                loaded[index].finishedAt = now()
                loaded[index].errorMessage = "NotchDo quit while this task was running."
                try persistence.save(loaded[index])
            }
            tasks = loaded.sorted { $0.createdAt > $1.createdAt }
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = "Could not load AI tasks: \(error.localizedDescription)"
        }
    }

    func task(id: UUID) -> AITask? {
        tasks.first { $0.id == id }
    }

    /// Applies `mutate` to a task and persists it. The in-memory copy changes even when saving
    /// fails, so the UI keeps reflecting reality; the error is returned for the caller to log.
    @discardableResult
    func update(_ id: UUID, _ mutate: (inout AITask) -> Void) -> Error? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&tasks[index])
        do {
            try persistence.save(tasks[index])
            return nil
        } catch {
            return error
        }
    }

    /// Deletes every finished task (done, failed, cancelled) and its files. Returns how many
    /// could not be deleted; those stay in the list.
    @discardableResult
    func removeFinished() -> Int {
        var failures = 0
        for task in tasks where task.status.isFinished {
            do {
                try persistence.delete(task.id)
                tasks.removeAll { $0.id == task.id }
            } catch {
                failures += 1
            }
        }
        return failures
    }

    /// Passes through to storage for the scheduler and the progress server.
    var storage: any AITaskPersisting { persistence }

    /// Creates and persists a queued task. Nothing is kept in memory if saving fails.
    @discardableResult
    func add(prompt: String) throws -> AITask {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AITaskStoreError.emptyPrompt }
        let task = AITask(prompt: trimmed, createdAt: now())
        try persistence.save(task)
        tasks.insert(task, at: 0)
        onTaskAdded?(task)
        return task
    }
}

import Foundation
import Testing
@testable import NotchDo

@Suite("AI task store")
@MainActor
struct AITaskStoreTests {
    private let now = fixedDate(2026, 10, 17, hour: 12)

    @Test("Adding a task persists it as queued and puts it first")
    func addPersists() throws {
        let persistence = FakeAITaskPersistence()
        let store = AITaskStore(persistence: persistence, now: { now })

        let first = try store.add(prompt: "  First task\nwith detail  ")
        let second = try store.add(prompt: "Second task")

        #expect(first.status == .queued)
        #expect(first.title == "First task")
        #expect(first.prompt == "First task\nwith detail")
        #expect(first.createdAt == now)
        #expect(store.tasks.map(\.id) == [second.id, first.id])
        #expect(persistence.savedTasks.map(\.id) == [first.id, second.id])
    }

    @Test("A blank prompt is rejected and nothing is saved")
    func blankPrompt() {
        let persistence = FakeAITaskPersistence()
        let store = AITaskStore(persistence: persistence)

        #expect(throws: AITaskStoreError.emptyPrompt) { try store.add(prompt: " \n ") }
        #expect(store.tasks.isEmpty)
        #expect(persistence.savedTasks.isEmpty)
    }

    @Test("A failed save leaves no task in memory")
    func saveFailureRollsBack() {
        let persistence = FakeAITaskPersistence()
        persistence.setFailsSaving(true)
        let store = AITaskStore(persistence: persistence)

        #expect(throws: FakeAITaskPersistence.Failure.self) { try store.add(prompt: "Will fail") }
        #expect(store.tasks.isEmpty)
    }

    @Test("Loading sorts newest first")
    func loadSorts() {
        let older = AITask(prompt: "Older", createdAt: fixedDate(2026, 10, 15))
        let newer = AITask(prompt: "Newer", createdAt: fixedDate(2026, 10, 16))
        let store = AITaskStore(persistence: FakeAITaskPersistence(tasks: [older, newer]))

        store.load()

        #expect(store.tasks.map(\.id) == [newer.id, older.id])
        #expect(store.loadErrorMessage == nil)
    }

    @Test("A task left running by a previous launch is closed out as failed and saved")
    func staleRunningTask() throws {
        var running = AITask(prompt: "Was running", status: .running, createdAt: fixedDate(2026, 10, 16))
        running.startedAt = fixedDate(2026, 10, 16, hour: 1)
        let queued = AITask(prompt: "Still queued", createdAt: fixedDate(2026, 10, 15))
        let persistence = FakeAITaskPersistence(tasks: [running, queued])
        let store = AITaskStore(persistence: persistence, now: { now })

        store.load()

        let recovered = try #require(store.tasks.first { $0.id == running.id })
        #expect(recovered.status == .failed)
        #expect(recovered.finishedAt == now)
        #expect(recovered.errorMessage != nil)
        #expect(store.tasks.first { $0.id == queued.id }?.status == .queued)
        #expect(persistence.savedTasks.map(\.id) == [running.id])
    }

    @Test("A load failure is reported instead of silently showing an empty list")
    func loadFailure() {
        let persistence = FakeAITaskPersistence()
        persistence.setFailsLoading(true)
        let store = AITaskStore(persistence: persistence)

        store.load()

        #expect(store.tasks.isEmpty)
        #expect(store.loadErrorMessage != nil)
    }
}

@Suite("AI task store cleanup")
@MainActor
struct AITaskStoreCleanupTests {
    @Test("Removing finished tasks keeps queued and running ones")
    func removeFinished() {
        let tasks = [
            AITask(prompt: "queued", status: .queued, createdAt: fixedDate(2026, 10, 10)),
            AITask(prompt: "done", status: .done, createdAt: fixedDate(2026, 10, 11)),
            AITask(prompt: "failed", status: .failed, createdAt: fixedDate(2026, 10, 12)),
            AITask(prompt: "cancelled", status: .cancelled, createdAt: fixedDate(2026, 10, 13))
        ]
        let persistence = FakeAITaskPersistence(tasks: tasks)
        let store = AITaskStore(persistence: persistence)
        store.load()

        let failures = store.removeFinished()

        #expect(failures == 0)
        #expect(store.tasks.map(\.prompt) == ["queued"])
        #expect(Set(persistence.deletedIDs) == Set(tasks.dropFirst().map(\.id)))
    }

    @Test("A task that cannot be deleted stays in the list and is counted")
    func deleteFailure() {
        let persistence = FakeAITaskPersistence(tasks: [AITask(prompt: "done", status: .done)])
        let store = AITaskStore(persistence: persistence)
        store.load()
        persistence.setFailsDeleting(true)

        #expect(store.removeFinished() == 1)
        #expect(store.tasks.count == 1)
    }

    @Test("Adding a task notifies the scheduler hook")
    func addNotifies() throws {
        let store = AITaskStore(persistence: FakeAITaskPersistence())
        var notified: [AITask] = []
        store.onTaskAdded = { notified.append($0) }

        let task = try store.add(prompt: "Hello")

        #expect(notified == [task])
    }

    @Test("Updating a task persists the change; unknown ids are ignored")
    func update() throws {
        let persistence = FakeAITaskPersistence()
        let store = AITaskStore(persistence: persistence)
        let task = try store.add(prompt: "Hello")

        let error = store.update(task.id) { $0.lastActivity = "Reading" }
        let missing = store.update(UUID()) { $0.lastActivity = "x" }

        #expect(error == nil && missing == nil)
        #expect(store.task(id: task.id)?.lastActivity == "Reading")
        #expect(persistence.savedTasks.last?.lastActivity == "Reading")

        persistence.setFailsSaving(true)
        #expect(store.update(task.id) { $0.lastActivity = "Writing" } != nil)
        #expect(store.task(id: task.id)?.lastActivity == "Writing")
    }
}

import Foundation

/// Read-only view of AI tasks for the progress server. Calls hop to the main actor, where
/// the task store lives.
protocol ProgressDataSource: Sendable {
    func tasks() async -> [AITask]
    func task(id: UUID) async -> AITask?
    func result(for id: UUID) async -> String?
    func eventLines(for id: UUID, after offset: Int) async -> [String]
}

struct StoreProgressDataSource: ProgressDataSource {
    let store: AITaskStore

    func tasks() async -> [AITask] {
        await MainActor.run { store.tasks }
    }

    func task(id: UUID) async -> AITask? {
        await MainActor.run { store.task(id: id) }
    }

    func result(for id: UUID) async -> String? {
        let storage = await MainActor.run { store.storage }
        return storage.result(for: id)
    }

    func eventLines(for id: UUID, after offset: Int) async -> [String] {
        let storage = await MainActor.run { store.storage }
        return (try? storage.eventLines(for: id, after: offset)) ?? []
    }
}

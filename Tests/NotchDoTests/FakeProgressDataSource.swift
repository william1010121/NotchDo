import Foundation
@testable import NotchDo

final class FakeProgressDataSource: ProgressDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var storedTasks: [AITask]
    private var results: [UUID: String]
    private var events: [UUID: [String]]

    init(tasks: [AITask] = [], results: [UUID: String] = [:], events: [UUID: [String]] = [:]) {
        storedTasks = tasks
        self.results = results
        self.events = events
    }

    func setTasks(_ tasks: [AITask]) { lock.withLock { storedTasks = tasks } }

    func tasks() async -> [AITask] { lock.withLock { storedTasks } }
    func task(id: UUID) async -> AITask? { lock.withLock { storedTasks.first { $0.id == id } } }
    func result(for id: UUID) async -> String? { lock.withLock { results[id] } }
    func eventLines(for id: UUID, after offset: Int) async -> [String] {
        lock.withLock { Array((events[id] ?? []).dropFirst(offset)) }
    }
}

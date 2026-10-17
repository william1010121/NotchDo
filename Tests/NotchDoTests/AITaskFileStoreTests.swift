import Foundation
import Testing
@testable import NotchDo

@Suite("AI task file store")
struct AITaskFileStoreTests {
    private func makeStore() -> (AITaskFileStore, AIWorkspace, URL) {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "NotchDoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let workspace = AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory))
        return (AITaskFileStore(workspace: workspace), workspace, base)
    }

    @Test("Loading before any task exists returns an empty list")
    func emptyWorkspace() throws {
        let (store, _, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(try store.loadAll().isEmpty)
    }

    @Test("A saved task is written to its own folder and loads back")
    func saveAndLoad() throws {
        let (store, workspace, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let task = AITask(prompt: "Tidy docs", createdAt: fixedDate(2026, 10, 17))

        try store.save(task)

        let file = workspace.taskURL(id: task.id).appending(path: "task.json", directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try store.loadAll() == [task])
    }

    @Test("Saving again replaces the previous version")
    func overwrite() throws {
        let (store, _, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        var task = AITask(prompt: "Tidy docs", createdAt: fixedDate(2026, 10, 17))
        try store.save(task)

        task.status = .done
        task.summary = "Finished"
        try store.save(task)

        let loaded = try store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded.first?.status == .done)
        #expect(loaded.first?.summary == "Finished")
    }

    @Test("An unreadable task folder is skipped without hiding the others")
    func corruptTaskIsSkipped() throws {
        let (store, workspace, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let good = AITask(prompt: "Good", createdAt: fixedDate(2026, 10, 17))
        try store.save(good)
        let badFolder = workspace.taskURL(id: UUID())
        try FileManager.default.createDirectory(at: badFolder, withIntermediateDirectories: true)
        try "{ not json".write(
            to: badFolder.appending(path: "task.json", directoryHint: .notDirectory),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: workspace.taskURL(id: UUID()),
            withIntermediateDirectories: true
        )

        #expect(try store.loadAll() == [good])
    }
}

@Suite("AI task file store run files")
struct AITaskFileStoreRunFileTests {
    private func makeStore() -> (AITaskFileStore, URL) {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "NotchDoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let workspace = AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory))
        return (AITaskFileStore(workspace: workspace), base)
    }

    @Test("Event lines append in order and can be read from an offset")
    func eventLog() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID()

        #expect(try store.eventLines(for: id, after: 0).isEmpty)
        try store.appendEventLine("{\"n\":1}", for: id)
        try store.appendEventLine("{\"n\":2}", for: id)
        try store.appendEventLine("{\"n\":3}", for: id)

        #expect(try store.eventLines(for: id, after: 0) == ["{\"n\":1}", "{\"n\":2}", "{\"n\":3}"])
        #expect(try store.eventLines(for: id, after: 2) == ["{\"n\":3}"])
        #expect(try store.eventLines(for: id, after: 10).isEmpty)
    }

    @Test("The result is saved to result.md and read back")
    func result() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID()

        #expect(store.result(for: id) == nil)
        try store.writeResult("All done\n設計完成", for: id)

        #expect(store.result(for: id) == "All done\n設計完成")
    }

    @Test("Resetting run files clears the log and result but keeps the task")
    func reset() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let task = AITask(prompt: "Keep me", createdAt: fixedDate(2026, 10, 17))
        try store.save(task)
        try store.appendEventLine("line", for: task.id)
        try store.writeResult("text", for: task.id)

        try store.resetRunFiles(for: task.id)

        #expect(try store.eventLines(for: task.id, after: 0).isEmpty)
        #expect(store.result(for: task.id) == nil)
        #expect(try store.loadAll() == [task])
    }

    @Test("Deleting a task removes its folder")
    func delete() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let task = AITask(prompt: "Remove me")
        try store.save(task)
        try store.writeResult("x", for: task.id)

        try store.delete(task.id)
        try store.delete(task.id)

        #expect(try store.loadAll().isEmpty)
    }

    @Test("A task file written by an earlier build, without newer fields, still loads")
    func olderFileLoads() throws {
        let (store, base) = makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID()
        let folder = base.appending(path: "NotchDo/.notchdo/tasks/\(id.uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = """
        {"id":"\(id.uuidString)","title":"Old","prompt":"Old prompt","status":"done","createdAt":"2026-10-17T12:00:00Z"}
        """
        try json.write(to: folder.appending(path: "task.json"), atomically: true, encoding: .utf8)

        let loaded = try #require(try store.loadAll().first)

        #expect(loaded.title == "Old")
        #expect(loaded.artifactURLs.isEmpty)
        #expect(loaded.followUps.isEmpty)
        #expect(loaded.sessionID == nil)
        #expect(loaded.pendingPrompt == nil)
    }
}

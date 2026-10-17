import Foundation
import OSLog

/// One folder per task: `<workspace>/.notchdo/tasks/<id>/task.json`, written atomically.
struct AITaskFileStore: AITaskPersisting {
    private static let fileName = "task.json"
    private static let eventsFileName = "events.jsonl"
    private static let resultFileName = "result.md"
    private static let logger = Logger(subsystem: "com.luku.NotchDo", category: "AITaskFileStore")

    let workspace: AIWorkspace

    func loadAll() throws -> [AITask] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: workspace.tasksURL.path) else { return [] }
        let folders = try fileManager.contentsOfDirectory(
            at: workspace.tasksURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return folders.compactMap { folder in
            let file = folder.appending(path: Self.fileName, directoryHint: .notDirectory)
            guard fileManager.fileExists(atPath: file.path) else { return nil }
            do {
                return try Self.decoder.decode(AITask.self, from: Data(contentsOf: file))
            } catch {
                Self.logger.error(
                    "Skipping unreadable task at \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    func save(_ task: AITask) throws {
        let folder = workspace.taskURL(id: task.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(task)
        try data.write(
            to: folder.appending(path: Self.fileName, directoryHint: .notDirectory),
            options: .atomic
        )
    }

    func appendEventLine(_ line: String, for id: UUID) throws {
        let folder = workspace.taskURL(id: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: Self.eventsFileName, directoryHint: .notDirectory)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    func eventLines(for id: UUID, after offset: Int) throws -> [String] {
        let file = workspace.taskURL(id: id).appending(path: Self.eventsFileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let text = try String(contentsOf: file, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.dropFirst(max(0, offset)))
    }

    func writeResult(_ text: String, for id: UUID) throws {
        let folder = workspace.taskURL(id: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text.write(
            to: folder.appending(path: Self.resultFileName, directoryHint: .notDirectory),
            atomically: true,
            encoding: .utf8
        )
    }

    func result(for id: UUID) -> String? {
        try? String(
            contentsOf: workspace.taskURL(id: id).appending(path: Self.resultFileName, directoryHint: .notDirectory),
            encoding: .utf8
        )
    }

    func delete(_ id: UUID) throws {
        let folder = workspace.taskURL(id: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func resetRunFiles(for id: UUID) throws {
        let folder = workspace.taskURL(id: id)
        for name in [Self.eventsFileName, Self.resultFileName] {
            let file = folder.appending(path: name, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

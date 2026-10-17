import Foundation
import Testing
@testable import NotchDo

@Suite("AI workspace")
struct AIWorkspaceTests {
    private func makeWorkspace() -> (AIWorkspace, URL) {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "NotchDoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory)), base)
    }

    @Test("Bootstrap creates the folder layout and a default CLAUDE.md")
    func bootstrapCreatesLayout() throws {
        let (workspace, base) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: base) }

        try workspace.bootstrap()

        var isDirectory: ObjCBool = false
        for url in [workspace.rootURL, workspace.projectsURL, workspace.tasksURL] {
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
        }
        let instructions = try String(contentsOf: workspace.claudeInstructionsURL, encoding: .utf8)
        #expect(instructions == AIWorkspace.defaultInstructions)
    }

    @Test("Bootstrap is idempotent and keeps a CLAUDE.md the user edited")
    func bootstrapPreservesEdits() throws {
        let (workspace, base) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: base) }
        try workspace.bootstrap()
        try "my own rules".write(to: workspace.claudeInstructionsURL, atomically: true, encoding: .utf8)

        try workspace.bootstrap()

        let instructions = try String(contentsOf: workspace.claudeInstructionsURL, encoding: .utf8)
        #expect(instructions == "my own rules")
    }

    @Test("Bootstrap keeps existing project files")
    func bootstrapPreservesProjects() throws {
        let (workspace, base) = makeWorkspace()
        defer { try? FileManager.default.removeItem(at: base) }
        try workspace.bootstrap()
        let file = workspace.projectsURL.appending(path: "demo.txt", directoryHint: .notDirectory)
        try "keep".write(to: file, atomically: true, encoding: .utf8)

        try workspace.bootstrap()

        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")
    }

    @Test("Paths follow the documented layout")
    func paths() {
        let id = UUID()
        let workspace = AIWorkspace(rootURL: URL(filePath: "/tmp/NotchDo", directoryHint: .isDirectory))

        #expect(workspace.tasksURL.path == "/tmp/NotchDo/.notchdo/tasks")
        #expect(workspace.portFileURL.path == "/tmp/NotchDo/.notchdo/port")
        #expect(workspace.taskURL(id: id).path == "/tmp/NotchDo/.notchdo/tasks/\(id.uuidString)")
    }

    @Test("The default workspace is ~/Desktop/NotchDo")
    func defaultLocation() {
        let path = AIWorkspace.defaultRootURL.path
        #expect(path.hasSuffix("/Desktop/NotchDo"))
        #expect(path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }
}

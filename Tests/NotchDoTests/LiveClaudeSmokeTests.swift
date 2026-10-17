import Foundation
import Testing
@testable import NotchDo

/// Opt-in end-to-end check against the real `claude` CLI (costs a few cents).
/// Run with: NOTCHDO_LIVE_CLAUDE=1 swift test --configuration release --filter LiveClaudeSmokeTests
@Suite(
    "Live Claude smoke test",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["NOTCHDO_LIVE_CLAUDE"] == "1")
)
@MainActor
struct LiveClaudeSmokeTests {
    @Test("A trivial task runs through the real CLI and completes")
    func endToEnd() async throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "NotchDoLive-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = AIWorkspace(rootURL: base.appending(path: "NotchDo", directoryHint: .isDirectory))
        try workspace.bootstrap()
        let store = AITaskStore(persistence: AITaskFileStore(workspace: workspace))
        var settings = AISettings()
        settings.publishArtifacts = false
        let locator = ClaudeExecutableLocator()
        let scheduler = AITaskScheduler(
            store: store,
            runner: ClaudeProcessRunner(),
            workspace: workspace,
            settings: { settings },
            locateClaude: { locator.locate(override: $0) }
        )

        let task = try store.add(prompt: "Create projects/hello/hello.txt containing the word hello, then reply with one short sentence.")
        scheduler.pump()
        await scheduler.waitUntilIdle()

        let finished = try #require(store.task(id: task.id))
        #expect(finished.status == .done, "error: \(finished.errorMessage ?? "none")")
        #expect(finished.summary?.isEmpty == false)
        #expect(finished.turnCount > 0)
        #expect(FileManager.default.fileExists(atPath: workspace.projectsURL.appending(path: "hello/hello.txt").path))
        let persistence = AITaskFileStore(workspace: workspace)
        #expect(persistence.result(for: task.id)?.isEmpty == false)
        #expect(try persistence.eventLines(for: task.id, after: 0).count > 2)
    }
}

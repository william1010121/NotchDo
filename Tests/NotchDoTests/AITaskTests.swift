import Foundation
import Testing
@testable import NotchDo

@Suite("AI task")
struct AITaskTests {
    @Test("The title is the first non-empty line, trimmed")
    func titleFromFirstLine() {
        #expect(AITask.makeTitle(from: "  \n\n  Refactor SettingsView \nthen add tests") == "Refactor SettingsView")
        #expect(AITask.makeTitle(from: "   \n  ") == "")
    }

    @Test("A long title is cut to the maximum length with an ellipsis")
    func titleTruncation() {
        let long = String(repeating: "a", count: 200)
        let title = AITask.makeTitle(from: long)

        #expect(title.count == AITask.maxTitleLength)
        #expect(title.hasSuffix("…"))
        #expect(AITask.makeTitle(from: String(repeating: "b", count: 80)).count == 80)
    }

    @Test("A task survives a JSON round trip")
    func codableRoundTrip() throws {
        var task = AITask(prompt: "Write a README", createdAt: fixedDate(2026, 10, 17, hour: 9))
        task.status = .done
        task.startedAt = fixedDate(2026, 10, 17, hour: 9, minute: 1)
        task.finishedAt = fixedDate(2026, 10, 17, hour: 9, minute: 5)
        task.summary = "Done"
        task.artifactURLs = [try #require(URL(string: "https://claude.ai/artifact/abc"))]
        task.turnCount = 3
        task.costUSD = 0.12

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AITask.self, from: encoder.encode(task))

        #expect(decoded == task)
    }

    @Test("Only queued and running tasks are unfinished")
    func finishedStatuses() {
        #expect(!AITaskStatus.queued.isFinished)
        #expect(!AITaskStatus.running.isFinished)
        #expect(AITaskStatus.done.isFinished)
        #expect(AITaskStatus.failed.isFinished)
        #expect(AITaskStatus.cancelled.isFinished)
    }
}

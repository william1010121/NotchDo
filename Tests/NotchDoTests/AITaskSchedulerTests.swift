import Foundation
import Testing
@testable import NotchDo

@Suite("AI task scheduler")
@MainActor
struct AITaskSchedulerTests {
    private let now = fixedDate(2026, 10, 17, hour: 12)
    private let claude = URL(filePath: "/usr/local/bin/claude")

    private struct Harness {
        let persistence: FakeAITaskPersistence
        let store: AITaskStore
        let runner: FakeClaudeRunner
        let scheduler: AITaskScheduler
        var finished: Box<[AITask]>
    }

    private final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private func makeHarness(
        settings: AISettings = AISettings(),
        claudeAvailable: Bool = true
    ) -> Harness {
        let persistence = FakeAITaskPersistence()
        let ticks = Box<TimeInterval>(0)
        let creationClock = now
        let store = AITaskStore(persistence: persistence, now: {
            ticks.value += 1
            return creationClock.addingTimeInterval(ticks.value)
        })
        let runner = FakeClaudeRunner()
        let claudeURL = claude
        let scheduler = AITaskScheduler(
            store: store,
            runner: runner,
            workspace: AIWorkspace(rootURL: URL(filePath: "/tmp/NotchDo", directoryHint: .isDirectory)),
            settings: { settings },
            locateClaude: { _ in claudeAvailable ? claudeURL : nil },
            now: { now }
        )
        let finished = Box<[AITask]>([])
        scheduler.onTaskFinished = { finished.value.append($0) }
        return Harness(persistence: persistence, store: store, runner: runner, scheduler: scheduler, finished: finished)
    }

    /// Polls (on the main actor) until `condition` holds; consumers run as main-actor tasks.
    private func waitUntil(
        _ message: Comment,
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), message)
    }

    @Test("A queued task starts with the configured request")
    func startsTask() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Refactor SettingsView")

        h.scheduler.pump()

        let request = try #require(h.runner.requests.first)
        #expect(request.prompt == "Refactor SettingsView")
        #expect(request.executable == claude)
        #expect(request.workingDirectory.path == "/tmp/NotchDo")
        #expect(request.sessionID == task.id)
        #expect(!request.resume)
        #expect(request.permissionMode == .acceptEdits)
        #expect(request.allowedTools.contains("Artifact"))
        #expect(request.appendSystemPrompt.contains(task.id.uuidString.lowercased()))
        let running = try #require(h.store.task(id: task.id))
        #expect(running.status == .running)
        #expect(running.startedAt == now)
        #expect(running.sessionID == task.id)
    }

    @Test("Progress updates the activity line, and a result completes the task")
    func completesTask() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Do work")
        h.scheduler.pump()

        h.runner.emit(ClaudeFixtures.initLine())
        h.runner.emit(ClaudeFixtures.toolUse(id: "t1", name: "Edit", input: #"{"file_path":"projects/a.swift"}"#))
        await waitUntil("activity line updates") {
            h.store.task(id: task.id)?.lastActivity == "Edit projects/a.swift"
        }

        h.runner.emit(ClaudeFixtures.result("Finished the work.\\nSecond line", turns: 5, cost: 0.4))
        h.runner.exit()
        await h.scheduler.waitUntilIdle()

        let done = try #require(h.store.task(id: task.id))
        #expect(done.status == .done)
        #expect(done.summary == "Finished the work.\nSecond line")
        #expect(done.turnCount == 5)
        #expect(done.costUSD == 0.4)
        #expect(done.finishedAt == now)
        #expect(done.lastActivity == nil)
        #expect(h.persistence.result(for: task.id) == "Finished the work.\nSecond line")
        #expect(try h.persistence.eventLines(for: task.id, after: 0).count == 3)
        #expect(h.finished.value.map(\.status) == [.done])
    }

    @Test("Only links from an Artifact publish call are attached to the task")
    func attachesPublishedArtifactOnly() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Make a report")
        h.scheduler.pump()

        h.runner.emit(ClaudeFixtures.toolUse(id: "list1", name: "Artifact", input: #"{"action":"list"}"#))
        h.runner.emit(ClaudeFixtures.toolResult(id: "list1", text: "- Other page https://claude.ai/artifact/OTHERPAGE1"))
        h.runner.emit(ClaudeFixtures.toolUse(id: "pub1", name: "Artifact", input: #"{"file_path":"/x/report.html"}"#))
        h.runner.emit(ClaudeFixtures.toolResult(id: "pub1", text: "Published https://claude.ai/artifact/NEWREPORT1 (Version 1)"))
        h.runner.emit(ClaudeFixtures.toolResult(id: "pub1", text: "Published again https://claude.ai/artifact/NEWREPORT1"))
        h.runner.emit(ClaudeFixtures.result("Report is ready."))
        h.runner.exit()
        await h.scheduler.waitUntilIdle()

        let urls = try #require(h.store.task(id: task.id)).artifactURLs.map(\.absoluteString)
        #expect(urls == ["https://claude.ai/artifact/NEWREPORT1"])
    }

    @Test("Only the configured number of tasks run at once; the next starts when one ends")
    func concurrencyLimit() async throws {
        let h = makeHarness()
        let first = try h.store.add(prompt: "First")
        let second = try h.store.add(prompt: "Second")

        h.scheduler.pump()

        #expect(h.runner.requests.count == 1)
        #expect(h.store.task(id: first.id)?.status == .running)
        #expect(h.store.task(id: second.id)?.status == .queued)

        h.runner.emit(ClaudeFixtures.result("one"), run: 0)
        h.runner.exit(run: 0)
        await waitUntil("second task starts") { h.runner.requests.count == 2 }

        #expect(h.runner.requests.count == 2)
        #expect(h.runner.requests[1].prompt == "Second")
        #expect(h.store.task(id: first.id)?.status == .done)
        #expect(h.store.task(id: second.id)?.status == .running)
        if h.runner.requests.count == 2 {
            h.runner.exit(status: 1, stderr: "boom", run: 1)
        }
        await h.scheduler.waitUntilIdle()
    }

    @Test("A higher limit runs tasks in parallel")
    func parallel() throws {
        var settings = AISettings()
        settings.maxConcurrent = 2
        let h = makeHarness(settings: settings)
        try h.store.add(prompt: "A")
        try h.store.add(prompt: "B")
        try h.store.add(prompt: "C")

        h.scheduler.pump()

        #expect(h.runner.requests.count == 2)
        #expect(h.scheduler.runningCount == 2)
    }

    @Test("Cancelling a running task stops the process and marks it cancelled")
    func cancelRunning() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Long job")
        h.scheduler.pump()

        h.scheduler.cancel(task.id)
        await h.scheduler.waitUntilIdle()

        #expect(h.runner.cancelCount == 1)
        let cancelled = try #require(h.store.task(id: task.id))
        #expect(cancelled.status == .cancelled)
        #expect(cancelled.errorMessage == nil)
        #expect(h.scheduler.runningCount == 0)
    }

    @Test("Cancelling a queued task never starts it")
    func cancelQueued() throws {
        let h = makeHarness()
        try h.store.add(prompt: "Running")
        let queued = try h.store.add(prompt: "Waiting")
        h.scheduler.pump()

        h.scheduler.cancel(queued.id)

        #expect(h.store.task(id: queued.id)?.status == .cancelled)
        #expect(h.runner.requests.count == 1)
    }

    @Test("A non-zero exit without a result fails with the stderr tail")
    func crashFails() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Crash")
        h.scheduler.pump()

        h.runner.exit(status: 2, stderr: "Error: not logged in")
        await h.scheduler.waitUntilIdle()

        let failed = try #require(h.store.task(id: task.id))
        #expect(failed.status == .failed)
        #expect(failed.errorMessage == "Error: not logged in")
    }

    @Test("A clean exit with no result is still a failure")
    func missingResult() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Silent")
        h.scheduler.pump()

        h.runner.exit(status: 0)
        await h.scheduler.waitUntilIdle()

        #expect(h.store.task(id: task.id)?.status == .failed)
    }

    @Test("An error result fails the task and keeps its message")
    func errorResult() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Hit a limit")
        h.scheduler.pump()

        h.runner.emit(ClaudeFixtures.result("Usage limit reached", isError: true))
        h.runner.exit(status: 1)
        await h.scheduler.waitUntilIdle()

        let failed = try #require(h.store.task(id: task.id))
        #expect(failed.status == .failed)
        #expect(failed.errorMessage == "Usage limit reached")
    }

    @Test("A missing Claude CLI fails the task with a helpful message")
    func claudeMissing() throws {
        let h = makeHarness(claudeAvailable: false)
        let task = try h.store.add(prompt: "Anything")

        h.scheduler.pump()

        let failed = try #require(h.store.task(id: task.id))
        #expect(failed.status == .failed)
        #expect(failed.errorMessage?.contains("Claude CLI not found") == true)
        #expect(h.runner.requests.isEmpty)
    }

    @Test("A launch failure fails the task instead of leaving it running")
    func launchFailure() throws {
        let h = makeHarness()
        h.runner.setFailsStarting(true)
        let task = try h.store.add(prompt: "Anything")

        h.scheduler.pump()

        #expect(h.store.task(id: task.id)?.status == .failed)
        #expect(h.scheduler.runningCount == 0)
    }

    @Test("Retry resets the task with a fresh session and runs it again")
    func retry() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Flaky")
        h.scheduler.pump()
        h.runner.emit(ClaudeFixtures.toolUse(id: "p", name: "Artifact", input: #"{"file_path":"/x.html"}"#))
        h.runner.emit(ClaudeFixtures.toolResult(id: "p", text: "https://claude.ai/artifact/OLD"))
        h.runner.exit(status: 1, stderr: "network down")
        await h.scheduler.waitUntilIdle()
        let firstSession = try #require(h.store.task(id: task.id)?.sessionID)

        h.scheduler.retry(task.id)

        #expect(h.runner.requests.count == 2)
        let second = h.runner.requests[1]
        #expect(second.sessionID != firstSession)
        #expect(!second.resume)
        let rerunning = try #require(h.store.task(id: task.id))
        #expect(rerunning.status == .running)
        #expect(rerunning.errorMessage == nil)
        #expect(rerunning.artifactURLs.isEmpty)
        h.runner.exit(run: 1)
        await h.scheduler.waitUntilIdle()
    }

    @Test("A follow-up resumes the same session with the new prompt")
    func followUp() async throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Write docs")
        h.scheduler.pump()
        h.runner.emit(ClaudeFixtures.result("Docs written."))
        h.runner.exit()
        await h.scheduler.waitUntilIdle()

        h.scheduler.followUp(task.id, prompt: "  Now translate them  ")

        let request = h.runner.requests[1]
        #expect(request.resume)
        #expect(request.sessionID == task.id)
        #expect(request.prompt == "Now translate them")
        let running = try #require(h.store.task(id: task.id))
        #expect(running.status == .running)
        #expect(running.followUps == ["Now translate them"])
        #expect(running.pendingPrompt == nil)
        h.runner.emit(ClaudeFixtures.result("Translated."), run: 1)
        h.runner.exit(run: 1)
        await h.scheduler.waitUntilIdle()
        #expect(h.store.task(id: task.id)?.summary == "Translated.")
    }

    @Test("Follow-ups are ignored for tasks that are not finished or the text is blank")
    func followUpGuards() throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Running soon")
        h.scheduler.pump()

        h.scheduler.followUp(task.id, prompt: "too early")

        #expect(h.store.task(id: task.id)?.pendingPrompt == nil)
        #expect(h.runner.requests.count == 1)
    }

    @Test("Quitting cancels running tasks immediately")
    func cancelAll() throws {
        let h = makeHarness()
        let task = try h.store.add(prompt: "Quit during run")
        h.scheduler.pump()

        h.scheduler.cancelAll()

        #expect(h.store.task(id: task.id)?.status == .cancelled)
        #expect(h.runner.cancelCount == 1)
        #expect(h.scheduler.runningCount == 0)
    }
}

import Foundation
import OSLog

/// Runs queued AI tasks through `claude -p`, at most `maxConcurrent` at a time, and keeps
/// each task's record, event log, and result file up to date.
@MainActor
final class AITaskScheduler {
    private struct ActiveRun {
        var cancel: @Sendable () -> Void
        var cancelRequested = false
        var artifactToolIDs: Set<String> = []
        var result: ClaudeResult?
    }

    private static let logger = Logger(subsystem: "com.luku.NotchDo", category: "AITaskScheduler")
    private static let summaryLimit = 600

    /// Called once a task reaches `done`, `failed`, or `cancelled`.
    var onTaskFinished: ((AITask) -> Void)?

    private let store: AITaskStore
    private let runner: any ClaudeRunning
    private let workspace: AIWorkspace
    private let settings: () -> AISettings
    private let locateClaude: (String) -> URL?
    private let now: () -> Date
    private var runs: [UUID: ActiveRun] = [:]
    private var loops: [UUID: Task<Void, Never>] = [:]

    init(
        store: AITaskStore,
        runner: any ClaudeRunning,
        workspace: AIWorkspace,
        settings: @escaping () -> AISettings,
        locateClaude: @escaping (String) -> URL?,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.runner = runner
        self.workspace = workspace
        self.settings = settings
        self.locateClaude = locateClaude
        self.now = now
    }

    var runningCount: Int { runs.count }

    /// Starts as many queued tasks as the concurrency limit allows.
    func pump() {
        let limit = settings().maxConcurrent
        while runs.count < limit,
              let next = store.tasks
                  .filter({ $0.status == .queued && runs[$0.id] == nil })
                  .min(by: { $0.createdAt < $1.createdAt }) {
            start(next)
        }
    }

    func cancel(_ id: UUID) {
        if runs[id] != nil {
            runs[id]?.cancelRequested = true
            runs[id]?.cancel()
        } else if store.task(id: id)?.status == .queued {
            finish(id, status: .cancelled, errorMessage: nil)
        }
    }

    func retry(_ id: UUID) {
        guard let task = store.task(id: id), task.status.isFinished, runs[id] == nil else { return }
        do { try store.storage.resetRunFiles(for: id) } catch { log("reset run files", error) }
        report(store.update(id) {
            $0.status = .queued
            $0.startedAt = nil
            $0.finishedAt = nil
            $0.summary = nil
            $0.lastActivity = nil
            $0.errorMessage = nil
            $0.artifactURLs = []
            $0.turnCount = 0
            $0.costUSD = nil
            $0.sessionID = UUID()
            $0.followUps = []
            $0.pendingPrompt = nil
        }, "save retry")
        pump()
    }

    /// Continues a finished task in its existing Claude session.
    func followUp(_ id: UUID, prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let task = store.task(id: id),
              task.status == .done || task.status == .failed, runs[id] == nil else { return }
        report(store.update(id) {
            $0.status = .queued
            $0.finishedAt = nil
            $0.errorMessage = nil
            $0.pendingPrompt = trimmed
        }, "save follow-up")
        pump()
    }

    /// Stops every running task. Used when the app quits.
    func cancelAll() {
        for id in Array(runs.keys) {
            runs[id]?.cancel()
            runs[id] = nil
            loops[id]?.cancel()
            loops[id] = nil
            finish(id, status: .cancelled, errorMessage: nil)
        }
    }

    /// Waits until no run is in flight. For tests.
    func waitUntilIdle() async {
        while let loop = loops.values.first {
            await loop.value
        }
    }

    // MARK: - Starting

    private func start(_ task: AITask) {
        let current = settings()
        guard let executable = locateClaude(current.claudePathOverride) else {
            finish(
                task.id,
                status: .failed,
                errorMessage: "Claude CLI not found. Install Claude Code or set its path in NotchDo Settings."
            )
            return
        }
        let followUpPrompt = task.pendingPrompt
        let sessionID = task.sessionID ?? task.id
        let request = ClaudeRunRequest(
            executable: executable,
            workingDirectory: workspace.rootURL,
            sessionID: sessionID,
            resume: followUpPrompt != nil,
            prompt: followUpPrompt ?? task.prompt,
            permissionMode: current.permissionMode,
            allowedTools: current.allowedTools,
            appendSystemPrompt: AIRunPrompt.systemPrompt(
                taskID: task.id,
                publishArtifacts: current.publishArtifacts
            )
        )
        report(store.update(task.id) {
            $0.status = .running
            $0.startedAt = now()
            $0.finishedAt = nil
            $0.errorMessage = nil
            $0.lastActivity = "Starting…"
            $0.sessionID = sessionID
            if let followUpPrompt {
                $0.followUps.append(followUpPrompt)
                $0.pendingPrompt = nil
            }
        }, "save start")

        let run: ClaudeRun
        do {
            run = try runner.start(request)
        } catch {
            finish(task.id, status: .failed, errorMessage: "Could not start Claude: \(error.localizedDescription)")
            return
        }
        let id = task.id
        runs[id] = ActiveRun(cancel: run.cancel)
        loops[id] = Task { [weak self] in
            for await event in run.events {
                self?.handle(event, for: id)
            }
        }
    }

    // MARK: - Events

    private func handle(_ event: ClaudeRunEvent, for id: UUID) {
        switch event {
        case .line(let line):
            do { try store.storage.appendEventLine(line, for: id) } catch { log("append event", error) }
            for parsed in ClaudeStreamParser.parse(line: line) { apply(parsed, to: id) }
        case .exited(let status, let stderrTail):
            handleExit(status: status, stderrTail: stderrTail, for: id)
        }
    }

    private func apply(_ event: ClaudeEvent, to id: UUID) {
        switch event {
        case .started:
            report(store.update(id) { $0.lastActivity = "Working…" }, "save activity")
        case .assistantText(let text):
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            report(store.update(id) { $0.lastActivity = Self.clipped(line) }, "save activity")
        case .toolUse(let toolID, let name, let detail, let publishes):
            if publishes { runs[id]?.artifactToolIDs.insert(toolID) }
            let activity = detail.map { "\(name) \($0)" } ?? name
            report(store.update(id) { $0.lastActivity = Self.clipped(activity) }, "save activity")
        case .toolResult(let toolID, let text):
            // Only links from a publish call belong to the task; `list` results mention other pages.
            guard runs[id]?.artifactToolIDs.contains(toolID) == true,
                  let url = ClaudeStreamParser.artifactURL(in: text) else { return }
            report(store.update(id) {
                if !$0.artifactURLs.contains(url) { $0.artifactURLs.append(url) }
            }, "save artifact link")
        case .result(let result):
            runs[id]?.result = result
            report(store.update(id) {
                $0.turnCount = result.turns
                if let cost = result.costUSD { $0.costUSD = (($0.costUSD ?? 0) + cost) }
            }, "save result")
        }
    }

    private func handleExit(status: Int32, stderrTail: String, for id: UUID) {
        let run = runs.removeValue(forKey: id)
        loops[id] = nil
        defer { pump() }

        if let text = run?.result?.text, !text.isEmpty {
            do { try store.storage.writeResult(text, for: id) } catch { log("write result", error) }
        }

        if run?.cancelRequested == true {
            finish(id, status: .cancelled, errorMessage: nil)
        } else if let result = run?.result {
            if result.isError {
                finish(id, status: .failed, errorMessage: result.text.isEmpty ? stderrTail : result.text, summary: nil)
            } else {
                finish(id, status: .done, errorMessage: nil, summary: result.text)
            }
        } else if status == 0 {
            finish(id, status: .failed, errorMessage: "Claude exited without a result.")
        } else {
            finish(
                id,
                status: .failed,
                errorMessage: stderrTail.isEmpty ? "Claude exited with status \(status)." : stderrTail
            )
        }
    }

    private func finish(_ id: UUID, status: AITaskStatus, errorMessage: String?, summary: String? = nil) {
        report(store.update(id) {
            $0.status = status
            $0.finishedAt = now()
            $0.lastActivity = nil
            $0.errorMessage = errorMessage.map(Self.errorClipped)
            if let summary { $0.summary = String(summary.prefix(Self.summaryLimit)) }
        }, "save final state")
        if let task = store.task(id: id) { onTaskFinished?(task) }
    }

    // MARK: - Helpers

    private static func clipped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 90 ? String(trimmed.prefix(89)) + "…" : trimmed
    }

    private static func errorClipped(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 1_000 ? String(trimmed.suffix(1_000)) : trimmed
    }

    private func report(_ error: Error?, _ action: String) {
        if let error { log(action, error) }
    }

    private func log(_ action: String, _ error: Error) {
        Self.logger.error("Could not \(action, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

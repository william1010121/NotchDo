import Foundation
import Testing
@testable import NotchDo

/// Exercises the real `Process` plumbing with a stand-in shell script instead of Claude.
@Suite("Claude process runner")
struct ClaudeProcessRunnerTests {
    private func makeScript(_ body: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NotchDoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appending(path: "fake-claude", directoryHint: .notDirectory)
        try ("#!/bin/sh\n" + body).write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, directory)
    }

    private func request(_ executable: URL, directory: URL, prompt: String = "hello") -> ClaudeRunRequest {
        ClaudeRunRequest(
            executable: executable,
            workingDirectory: directory,
            sessionID: UUID(),
            resume: false,
            prompt: prompt,
            permissionMode: .plan,
            allowedTools: [],
            appendSystemPrompt: ""
        )
    }

    private func collect(_ run: ClaudeRun) async -> [ClaudeRunEvent] {
        var events: [ClaudeRunEvent] = []
        for await event in run.events { events.append(event) }
        return events
    }

    @Test("The prompt arrives on stdin and stdout is delivered line by line, then the exit")
    func roundTrip() async throws {
        let (script, directory) = try makeScript("""
        read -r prompt
        echo "{\\"echo\\":\\"$prompt\\"}"
        echo "{\\"cwd\\":\\"$(pwd)\\"}"
        echo "warning on stderr" >&2
        exit 0
        """)
        defer { try? FileManager.default.removeItem(at: directory) }

        let run = try ClaudeProcessRunner().start(request(script, directory: directory, prompt: "ping"))
        let events = await collect(run)

        #expect(events.count == 3)
        #expect(events.first == .line(#"{"echo":"ping"}"#))
        guard case .line(let cwdLine) = events[1] else {
            Issue.record("Expected a cwd line")
            return
        }
        #expect(cwdLine.contains(directory.lastPathComponent))
        #expect(events.last == .exited(status: 0, stderrTail: "warning on stderr"))
    }

    @Test("A failing process reports its status and stderr")
    func failure() async throws {
        let (script, directory) = try makeScript("echo 'not logged in' >&2\nexit 3\n")
        defer { try? FileManager.default.removeItem(at: directory) }

        let events = await collect(try ClaudeProcessRunner().start(request(script, directory: directory)))

        #expect(events == [.exited(status: 3, stderrTail: "not logged in")])
    }

    @Test("Cancelling terminates a long-running process")
    func cancel() async throws {
        let (script, directory) = try makeScript("echo started\nsleep 30\n")
        defer { try? FileManager.default.removeItem(at: directory) }

        let run = try ClaudeProcessRunner().start(request(script, directory: directory))
        var sawStart = false
        var exitStatus: Int32?
        let clock = ContinuousClock()
        let began = clock.now
        for await event in run.events {
            switch event {
            case .line:
                sawStart = true
                run.cancel()
            case .exited(let status, _):
                exitStatus = status
            }
        }

        #expect(sawStart)
        #expect(exitStatus != nil && exitStatus != 0)
        #expect(clock.now - began < .seconds(10))
    }

    @Test("A missing executable throws instead of crashing")
    func missingExecutable() {
        let missing = URL(filePath: "/nonexistent/claude")

        #expect(throws: (any Error).self) {
            try ClaudeProcessRunner().start(request(missing, directory: FileManager.default.temporaryDirectory))
        }
    }
}

import Foundation

/// Runs the real `claude` CLI as a child process. Children that Claude itself spawns (shell
/// commands) are not tracked: cancelling stops Claude, which then stops its own tools.
struct ClaudeProcessRunner: ClaudeRunning {
    private static let stderrLimit = 8_000
    private static let drainGrace: TimeInterval = 1

    func start(_ request: ClaudeRunRequest) throws -> ClaudeRun {
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory
        process.environment = Self.environment()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let (stream, continuation) = AsyncStream.makeStream(of: ClaudeRunEvent.self)
        let outBuffer = LineBuffer()
        let errorTail = StderrTail(limit: Self.stderrLimit)
        let drained = DispatchGroup()
        for _ in 0..<3 { drained.enter() }

        let stdoutDone = LeaveOnce(drained)
        let stderrDone = LeaveOnce(drained)
        let processDone = LeaveOnce(drained)

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let rest = outBuffer.flush() { continuation.yield(.line(rest)) }
                stdoutDone.leave()
                return
            }
            for line in outBuffer.append(data) { continuation.yield(.line(line)) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stderrDone.leave()
                return
            }
            errorTail.append(data)
        }
        process.terminationHandler = { _ in
            processDone.leave()
            // Tools that Claude started can keep the pipes open after Claude itself is gone.
            // Give the pipes a moment to drain, then stop waiting for them.
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.drainGrace) {
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                if let rest = outBuffer.flush() { continuation.yield(.line(rest)) }
                stdoutDone.leave()
                stderrDone.leave()
            }
        }
        drained.notify(queue: .global()) { [process] in
            continuation.yield(.exited(status: process.terminationStatus, stderrTail: errorTail.text))
            continuation.finish()
        }

        try process.run()
        let promptData = Data(request.prompt.utf8)
        DispatchQueue.global().async {
            try? stdin.fileHandleForWriting.write(contentsOf: promptData)
            try? stdin.fileHandleForWriting.close()
        }

        let handle = ProcessHandle(process)
        return ClaudeRun(events: stream, cancel: { handle.stop() })
    }

    private static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let existing = environment["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        environment["PATH"] = (extra + existing.filter { !extra.contains($0) }).joined(separator: ":")
        return environment
    }
}

/// Cancels a process politely, then forcefully if it ignores SIGTERM.
private final class ProcessHandle: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

private final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
            if data.count > limit { data = data.suffix(limit) }
        }
    }

    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

/// Leaves a dispatch group at most once, however many paths race to do it.
private final class LeaveOnce: @unchecked Sendable {
    private let lock = NSLock()
    private let group: DispatchGroup
    private var didLeave = false

    init(_ group: DispatchGroup) {
        self.group = group
    }

    func leave() {
        let shouldLeave = lock.withLock {
            defer { didLeave = true }
            return !didLeave
        }
        if shouldLeave { group.leave() }
    }
}

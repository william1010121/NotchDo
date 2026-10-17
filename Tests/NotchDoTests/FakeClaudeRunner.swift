import Foundation
@testable import NotchDo

/// Hands out controllable runs so tests decide when output arrives and when a process exits.
final class FakeClaudeRunner: ClaudeRunning, @unchecked Sendable {
    struct StartFailure: Error {}

    private let lock = NSLock()
    private var continuations: [AsyncStream<ClaudeRunEvent>.Continuation] = []
    private var requestLog: [ClaudeRunRequest] = []
    private var cancelCountValue = 0
    private var failsStarting = false

    var requests: [ClaudeRunRequest] { lock.withLock { requestLog } }
    var cancelCount: Int { lock.withLock { cancelCountValue } }

    func setFailsStarting(_ value: Bool) { lock.withLock { failsStarting = value } }

    func start(_ request: ClaudeRunRequest) throws -> ClaudeRun {
        try lock.withLock {
            if failsStarting { throw StartFailure() }
            requestLog.append(request)
        }
        let (stream, continuation) = AsyncStream.makeStream(of: ClaudeRunEvent.self)
        lock.withLock { continuations.append(continuation) }
        return ClaudeRun(events: stream, cancel: { [self] in
            lock.withLock { cancelCountValue += 1 }
            // A cancelled process exits with a signal status.
            continuation.yield(.exited(status: 15, stderrTail: ""))
            continuation.finish()
        })
    }

    func emit(_ line: String, run index: Int = 0) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(.line(line))
    }

    func exit(status: Int32 = 0, stderr: String = "", run index: Int = 0) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(.exited(status: status, stderrTail: stderr))
        continuation.finish()
    }
}

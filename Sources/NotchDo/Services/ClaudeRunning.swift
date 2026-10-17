import Foundation

enum ClaudeRunEvent: Equatable, Sendable {
    /// One raw stdout line (a stream-json object).
    case line(String)
    /// The process ended and both pipes are drained. Always the last event.
    case exited(status: Int32, stderrTail: String)
}

/// A started Claude process: its output stream and a way to stop it.
struct ClaudeRun: Sendable {
    let events: AsyncStream<ClaudeRunEvent>
    let cancel: @Sendable () -> Void
}

/// Seam over the `claude` process so the scheduler is tested with fakes and the demo build
/// never launches the real CLI.
protocol ClaudeRunning: Sendable {
    func start(_ request: ClaudeRunRequest) throws -> ClaudeRun
}

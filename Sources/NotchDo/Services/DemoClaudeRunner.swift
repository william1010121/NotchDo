#if NOTCHDO_DEMO
import Foundation

/// Stand-in for the `claude` CLI in the demo build: replays a short, fictional run so the
/// UI can be checked without launching Claude or spending anything.
struct DemoClaudeRunner: ClaudeRunning {
    func start(_ request: ClaudeRunRequest) throws -> ClaudeRun {
        let (stream, continuation) = AsyncStream.makeStream(of: ClaudeRunEvent.self)
        let session = request.sessionID.uuidString.lowercased()
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"\#(session)","model":"demo"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Reading the project first."}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"projects/demo/README.md"}}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"projects/demo/main.swift"}}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"num_turns":3,"result":"Demo task finished. Nothing was changed.","total_cost_usd":0}"#
        ]
        let worker = Task {
            for line in lines {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                continuation.yield(.line(line))
            }
            continuation.yield(.exited(status: 0, stderrTail: ""))
            continuation.finish()
        }
        return ClaudeRun(events: stream, cancel: {
            worker.cancel()
            continuation.yield(.exited(status: 15, stderrTail: ""))
            continuation.finish()
        })
    }
}
#endif

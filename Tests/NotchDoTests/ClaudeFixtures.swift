import Foundation

/// Stream-json lines shaped like real `claude -p --output-format stream-json --verbose` output.
enum ClaudeFixtures {
    static func initLine(session: String = "11111111-1111-1111-1111-111111111111") -> String {
        #"{"type":"system","subtype":"init","session_id":"\#(session)","model":"claude-opus-5-5","tools":["Read"]}"#
    }

    static func text(_ text: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    static func toolUse(id: String, name: String, input: String) -> String {
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
    }

    static func toolResult(id: String, text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"\#(id)","type":"tool_result","content":"\#(text)"}]}}"#
    }

    static func result(
        _ text: String,
        isError: Bool = false,
        turns: Int = 3,
        cost: Double = 0.25
    ) -> String {
        #"{"type":"result","subtype":"success","is_error":\#(isError),"num_turns":\#(turns),"result":"\#(text)","total_cost_usd":\#(cost)}"#
    }
}

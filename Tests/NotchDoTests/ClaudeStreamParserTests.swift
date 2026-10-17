import Foundation
import Testing
@testable import NotchDo

@Suite("Claude stream parser")
struct ClaudeStreamParserTests {
    @Test("The init line reports the session and model")
    func initLine() {
        let events = ClaudeStreamParser.parse(line: ClaudeFixtures.initLine(session: "abc"))

        #expect(events == [.started(sessionID: "abc", model: "claude-opus-5-5")])
    }

    @Test("Assistant text becomes a text event; empty text is ignored")
    func assistantText() {
        #expect(ClaudeStreamParser.parse(line: ClaudeFixtures.text("Working on it")) == [.assistantText("Working on it")])
        #expect(ClaudeStreamParser.parse(line: ClaudeFixtures.text("  ")).isEmpty)
    }

    @Test("Tool use carries a short target and flags Artifact publishes")
    func toolUse() {
        let read = ClaudeStreamParser.parse(
            line: ClaudeFixtures.toolUse(id: "t1", name: "Read", input: #"{"file_path":"projects/a.swift"}"#)
        )
        let publish = ClaudeStreamParser.parse(
            line: ClaudeFixtures.toolUse(id: "t2", name: "Artifact", input: #"{"file_path":"/tmp/x.html","icon":"chart"}"#)
        )
        let explicitPublish = ClaudeStreamParser.parse(
            line: ClaudeFixtures.toolUse(id: "t3", name: "Artifact", input: #"{"action":"publish"}"#)
        )
        let list = ClaudeStreamParser.parse(
            line: ClaudeFixtures.toolUse(id: "t4", name: "Artifact", input: #"{"action":"list","limit":1}"#)
        )

        #expect(read == [.toolUse(id: "t1", name: "Read", detail: "projects/a.swift", publishesArtifact: false)])
        #expect(publish == [.toolUse(id: "t2", name: "Artifact", detail: "/tmp/x.html", publishesArtifact: true)])
        #expect(explicitPublish == [.toolUse(id: "t3", name: "Artifact", detail: "publish", publishesArtifact: true)])
        #expect(list == [.toolUse(id: "t4", name: "Artifact", detail: "list", publishesArtifact: false)])
    }

    @Test("A long command is cut to one short line")
    func longDetail() {
        let command = String(repeating: "x", count: 200) + "\\nsecond line"
        let events = ClaudeStreamParser.parse(
            line: ClaudeFixtures.toolUse(id: "t", name: "Bash", input: #"{"command":"\#(command)"}"#)
        )

        guard case .toolUse(_, _, let detail?, _) = events.first else {
            Issue.record("Expected a tool use with detail")
            return
        }
        #expect(detail.count == 80)
        #expect(detail.hasSuffix("…"))
    }

    @Test("Tool results are parsed from string and block content")
    func toolResults() {
        let plain = ClaudeStreamParser.parse(line: ClaudeFixtures.toolResult(id: "t1", text: "done"))
        let blocks = ClaudeStreamParser.parse(
            line: #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":[{"type":"text","text":"a"},{"type":"text","text":"b"}]}]}}"#
        )

        #expect(plain == [.toolResult(id: "t1", text: "done")])
        #expect(blocks == [.toolResult(id: "t2", text: "a\nb")])
    }

    @Test("The result line carries text, error flag, turns, and cost")
    func result() {
        let events = ClaudeStreamParser.parse(line: ClaudeFixtures.result("All done", turns: 4, cost: 0.5))

        #expect(events == [.result(ClaudeResult(text: "All done", isError: false, turns: 4, costUSD: 0.5))])
    }

    @Test("Noise, partial deltas, and malformed lines produce no events")
    func ignoredLines() {
        #expect(ClaudeStreamParser.parse(line: "not json").isEmpty)
        #expect(ClaudeStreamParser.parse(line: "").isEmpty)
        #expect(ClaudeStreamParser.parse(line: #"{"type":"stream_event","event":{}}"#).isEmpty)
        #expect(ClaudeStreamParser.parse(line: #"{"type":"system","subtype":"status"}"#).isEmpty)
        #expect(ClaudeStreamParser.parse(line: #"{"type":"rate_limit_event"}"#).isEmpty)
        #expect(ClaudeStreamParser.parse(line: #"{"no_type":true}"#).isEmpty)
    }

    @Test("Artifact links are found in tool output")
    func artifactURL() {
        let text = "Published https://claude.ai/artifact/4nW6QNF4DCDvTu9tnL6aZY (Version 2). Done."

        #expect(ClaudeStreamParser.artifactURL(in: text)?.absoluteString == "https://claude.ai/artifact/4nW6QNF4DCDvTu9tnL6aZY")
        #expect(ClaudeStreamParser.artifactURL(in: "see https://claude.ai/code/artifact/abc-123_x")?.lastPathComponent == "abc-123_x")
        #expect(ClaudeStreamParser.artifactURL(in: "https://example.com/artifact/abc") == nil)
        #expect(ClaudeStreamParser.artifactURL(in: "no link") == nil)
    }
}

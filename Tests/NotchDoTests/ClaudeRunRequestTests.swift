import Foundation
import Testing
@testable import NotchDo

@Suite("Claude run request")
struct ClaudeRunRequestTests {
    private let session = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func request(
        mode: AIPermissionMode = .acceptEdits,
        resume: Bool = false,
        tools: [String] = ["Read", "Bash(git:*)"],
        system: String = "be brief"
    ) -> ClaudeRunRequest {
        ClaudeRunRequest(
            executable: URL(filePath: "/usr/local/bin/claude"),
            workingDirectory: URL(filePath: "/tmp/NotchDo"),
            sessionID: session,
            resume: resume,
            prompt: "do it",
            permissionMode: mode,
            allowedTools: tools,
            appendSystemPrompt: system
        )
    }

    @Test("A new run uses --session-id, streams JSON, and limits tools")
    func newRun() {
        #expect(request().arguments == [
            "-p", "--output-format", "stream-json", "--verbose",
            "--session-id", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "--permission-mode", "acceptEdits",
            "--allowedTools", "Read,Bash(git:*)",
            "--append-system-prompt", "be brief"
        ])
    }

    @Test("A follow-up resumes the existing session")
    func resume() {
        let arguments = request(resume: true).arguments

        #expect(arguments.contains("--resume"))
        #expect(!arguments.contains("--session-id"))
    }

    @Test("Plan and full-access modes do not pass an allowlist")
    func noAllowlist() {
        #expect(!request(mode: .plan).arguments.contains("--allowedTools"))
        #expect(!request(mode: .bypassPermissions).arguments.contains("--allowedTools"))
        #expect(request(mode: .plan).arguments.contains("plan"))
    }

    @Test("An empty system prompt is omitted")
    func emptySystemPrompt() {
        #expect(!request(system: "").arguments.contains("--append-system-prompt"))
    }

    @Test("The prompt is never part of the arguments")
    func promptNotInArguments() {
        #expect(!request().arguments.contains("do it"))
    }
}

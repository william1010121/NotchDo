import Foundation
import Testing
@testable import NotchDo

@Suite("AI task badge state")
struct AITaskBadgeStateTests {
    private func task(_ status: AITaskStatus) -> AITask {
        AITask(prompt: "x", status: status)
    }

    @Test("With no tasks the badge counts zero and is idle")
    func empty() {
        let state = AITaskBadgeState(tasks: [])

        #expect(state.openCount == 0)
        #expect(!state.isRunning)
    }

    @Test("Finished tasks are not counted")
    func finishedIgnored() {
        let state = AITaskBadgeState(tasks: [task(.done), task(.failed), task(.cancelled)])

        #expect(state.openCount == 0)
        #expect(!state.isRunning)
    }

    @Test("Queued and running tasks are counted, and any running task marks it active")
    func openCount() {
        let state = AITaskBadgeState(tasks: [task(.queued), task(.running), task(.running), task(.done)])

        #expect(state.openCount == 3)
        #expect(state.isRunning)
        #expect(AITaskBadgeState(tasks: [task(.queued), task(.queued)]) == AITaskBadgeState(tasks: [task(.queued), task(.queued)]))
        #expect(!AITaskBadgeState(tasks: [task(.queued)]).isRunning)
    }

    @Test("VoiceOver text reflects the count and activity")
    func accessibility() {
        #expect(AITaskBadgeState(tasks: []).accessibilityLabel == "0 AI tasks open")
        #expect(AITaskBadgeState(tasks: [task(.queued)]).accessibilityLabel == "1 AI task open")
        #expect(AITaskBadgeState(tasks: [task(.running), task(.queued)]).accessibilityLabel == "2 AI tasks open, Claude is working")
    }
}

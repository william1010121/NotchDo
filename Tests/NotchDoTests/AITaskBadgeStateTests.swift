import Foundation
import Testing
@testable import NotchDo

@Suite("AI task badge state")
struct AITaskBadgeStateTests {
    private func task(_ status: AITaskStatus) -> AITask {
        AITask(prompt: "x", status: status)
    }

    @Test("Nothing active hides the badge")
    func hidden() {
        #expect(AITaskBadgeState(tasks: []) == .hidden)
        #expect(AITaskBadgeState(tasks: [task(.done), task(.failed), task(.cancelled)]) == .hidden)
    }

    @Test("Running work takes priority over queued work")
    func runningFirst() {
        #expect(AITaskBadgeState(tasks: [task(.queued), task(.running), task(.running)]) == .running(2))
    }

    @Test("Only queued work shows the queue length")
    func queued() {
        #expect(AITaskBadgeState(tasks: [task(.queued), task(.done), task(.queued)]) == .queued(2))
    }

    @Test("VoiceOver text reflects the state")
    func accessibility() {
        #expect(AITaskBadgeState.hidden.accessibilityLabel == nil)
        #expect(AITaskBadgeState.running(1).accessibilityLabel == "1 AI task running")
        #expect(AITaskBadgeState.queued(3).accessibilityLabel == "3 AI tasks queued")
    }
}

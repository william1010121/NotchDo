import Foundation
import Testing
@testable import NotchDo

@Suite("AI capture session")
@MainActor
struct AICaptureSessionTests {
    @Test("Submitting needs a non-blank prompt")
    func canSubmit() {
        let session = AICaptureSession(store: AITaskStore(persistence: FakeAITaskPersistence()))

        #expect(!session.canSubmit)
        session.prompt = "  \n "
        #expect(!session.canSubmit)
        #expect(!session.submit())
        session.prompt = "Do the thing"
        #expect(session.canSubmit)
    }

    @Test("A successful submit stores the task")
    func submitStores() {
        let store = AITaskStore(persistence: FakeAITaskPersistence())
        let session = AICaptureSession(store: store)
        session.prompt = "Summarize the repo"

        #expect(session.submit())
        #expect(store.tasks.map(\.prompt) == ["Summarize the repo"])
        #expect(session.errorMessage == nil)
    }

    @Test("A failed save keeps the prompt and shows an error")
    func submitFailure() {
        let persistence = FakeAITaskPersistence()
        persistence.setFailsSaving(true)
        let session = AICaptureSession(store: AITaskStore(persistence: persistence))
        session.prompt = "Summarize the repo"

        #expect(!session.submit())
        #expect(session.prompt == "Summarize the repo")
        #expect(session.errorMessage != nil)
    }

    @Test("Preparing a new presentation clears the prompt and error")
    func prepareResets() {
        let persistence = FakeAITaskPersistence()
        persistence.setFailsSaving(true)
        let session = AICaptureSession(store: AITaskStore(persistence: persistence))
        session.prompt = "Leftover"
        _ = session.submit()
        let before = session.presentationID

        session.prepare()

        #expect(session.prompt.isEmpty)
        #expect(session.errorMessage == nil)
        #expect(session.presentationID == before &+ 1)
    }
}

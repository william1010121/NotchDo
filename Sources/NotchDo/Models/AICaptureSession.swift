import Foundation
import Observation

/// State of one AI Capture panel presentation.
@MainActor
@Observable
final class AICaptureSession {
    var prompt = ""
    /// Shown in the panel's hint line; updated on each presentation because it can change in Settings.
    var shortcutHint = ""
    private(set) var errorMessage: String?
    private(set) var presentationID = 0
    private let store: AITaskStore

    init(store: AITaskStore) {
        self.store = store
    }

    var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepare() {
        presentationID &+= 1
        prompt = ""
        errorMessage = nil
    }

    /// Returns true when the task was saved and the panel can close.
    func submit() -> Bool {
        guard canSubmit else { return false }
        do {
            try store.add(prompt: prompt)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

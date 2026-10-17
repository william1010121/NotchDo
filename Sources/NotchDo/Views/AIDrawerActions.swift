import Foundation

/// Operations the drawer can offer on a task. A nil closure hides its control.
struct AIDrawerActions {
    var cancel: ((AITask) -> Void)?
    var retry: ((AITask) -> Void)?
    var followUp: ((AITask, String) -> Void)?
    var reveal: ((AITask) -> Void)?
    var openProgressPage: (() -> Void)?
    var openArtifact: ((URL) -> Void)?
    var newTask: () -> Void = {}
}

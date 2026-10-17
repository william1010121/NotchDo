import Foundation

/// Tells the user a task finished while they are in another app.
@MainActor
protocol AINotifying: AnyObject {
    /// Called with the task id when the user clicks a notification.
    var onOpenTask: ((UUID) -> Void)? { get set }
    func notifyFinished(_ task: AITask)
}

import Foundation
import UserNotifications

/// Posts a system notification when an AI task finishes. Authorization is requested the first
/// time one is needed, not at launch.
@MainActor
final class AINotifier: NSObject, AINotifying, UNUserNotificationCenterDelegate {
    var onOpenTask: ((UUID) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func notifyFinished(_ task: AITask) {
        guard task.status != .cancelled else { return }
        let content = UNMutableNotificationContent()
        switch task.status {
        case .done:
            content.title = "Done: \(task.title)"
            content.body = task.summary.map { String($0.prefix(140)) } ?? "Claude finished this task."
        default:
            content.title = "Failed: \(task.title)"
            content.body = task.errorMessage.map { String($0.prefix(140)) } ?? "Claude could not finish this task."
        }
        content.userInfo = ["taskID": task.id.uuidString]
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: nil)
        let center = center
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run { onOpenTask?(id) }
    }
}

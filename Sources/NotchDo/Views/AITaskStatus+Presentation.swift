import SwiftUI

extension AITaskStatus {
    var symbolName: String {
        switch self {
        case .queued: "circle"
        case .running: "circle.inset.filled"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .queued: Color.white.opacity(0.5)
        case .running: Color(red: 0.25, green: 0.82, blue: 0.64)
        case .done: Color(red: 0.25, green: 0.82, blue: 0.64).opacity(0.7)
        case .failed: Color(red: 0.94, green: 0.54, blue: 0.47)
        case .cancelled: Color.white.opacity(0.4)
        }
    }

    /// Spoken by VoiceOver so state never depends on color alone.
    var accessibilityName: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .done: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

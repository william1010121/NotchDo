enum AITaskStatus: String, Codable, Sendable {
    case queued
    case running
    case done
    case failed
    case cancelled

    var isFinished: Bool {
        switch self {
        case .done, .failed, .cancelled: true
        case .queued, .running: false
        }
    }
}

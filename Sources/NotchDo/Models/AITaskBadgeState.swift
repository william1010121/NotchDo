/// What the collapsed notch shows to the right of the hardware cutout.
enum AITaskBadgeState: Equatable {
    case hidden
    case running(Int)
    case queued(Int)

    init(tasks: [AITask]) {
        let running = tasks.filter { $0.status == .running }.count
        let queued = tasks.filter { $0.status == .queued }.count
        if running > 0 {
            self = .running(running)
        } else if queued > 0 {
            self = .queued(queued)
        } else {
            self = .hidden
        }
    }

    var accessibilityLabel: String? {
        switch self {
        case .hidden: nil
        case .running(let count): count == 1 ? "1 AI task running" : "\(count) AI tasks running"
        case .queued(let count): count == 1 ? "1 AI task queued" : "\(count) AI tasks queued"
        }
    }
}

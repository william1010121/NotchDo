/// What the collapsed notch shows to the right of the hardware cutout: the number of
/// unfinished AI tasks, mirroring the open-reminder count on the left.
struct AITaskBadgeState: Equatable {
    var openCount: Int
    var isRunning: Bool

    init(tasks: [AITask]) {
        openCount = tasks.filter { $0.status == .queued || $0.status == .running }.count
        isRunning = tasks.contains { $0.status == .running }
    }

    var accessibilityLabel: String {
        let noun = openCount == 1 ? "AI task" : "AI tasks"
        return isRunning ? "\(openCount) \(noun) open, Claude is working" : "\(openCount) \(noun) open"
    }
}

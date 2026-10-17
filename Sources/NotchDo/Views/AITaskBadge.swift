import SwiftUI

/// Collapsed-notch indicator for AI work, mirrored on the opposite side of the reminder
/// `TaskCountBadge`. Blue, and it pulses while Claude is working.
struct AITaskBadge: View {
    static let color = Color(red: 0.30, green: 0.55, blue: 1.0)

    let state: AITaskBadgeState
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        TaskCountBadge(count: state.openCount, color: Self.color, diameter: diameter)
            .opacity(state.isRunning && isPulsing && !reduceMotion ? 0.55 : 1)
            .animation(
                state.isRunning && !reduceMotion
                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { isPulsing = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.accessibilityLabel)
    }
}

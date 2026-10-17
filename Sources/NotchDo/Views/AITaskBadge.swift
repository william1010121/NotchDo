import SwiftUI

/// Collapsed-notch indicator for AI work, mirrored on the opposite side of `TaskCountBadge`.
struct AITaskBadge: View {
    let state: AITaskBadgeState
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Group {
            switch state {
            case .hidden:
                EmptyView()
            case .running(let count):
                badge(label: count > 1 ? "\(count)" : nil, tint: AITaskStatus.running.tint)
                    .opacity(isPulsing && !reduceMotion ? 0.55 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
            case .queued(let count):
                badge(label: "\(count)", tint: AITaskStatus.queued.tint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel ?? "")
    }

    private func badge(label: String?, tint: Color) -> some View {
        ZStack {
            Circle().fill(tint)
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.72))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

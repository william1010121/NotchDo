import SwiftUI

/// The AI task list that hangs to the right of the expanded notch. The AppKit panel is a
/// fixed surface; only the mask animates, like `NotchRootView`.
struct AIDrawerView: View {
    let store: AITaskStore
    let progressServer: LocalProgressServer
    @ObservedObject var layout: NotchLayoutModel
    @ObservedObject var interaction: NotchInteractionModel
    let shortcutHint: String
    let actions: AIDrawerActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedTaskID: AITask.ID?

    private var isExpanded: Bool { interaction.isExpanded }
    private var panelSize: CGSize {
        CGSize(width: AIDrawerMetrics.width, height: layout.metrics.expandedSize.height)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            VStack(spacing: 0) {
                Color.clear.frame(height: layout.metrics.bridgeHeight + 2)
                content
                    .padding(.horizontal, AIDrawerMetrics.flareRadius + 14)
                    .padding(.bottom, 16)
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
        }
        .mask(alignment: .topLeading) {
            NotchSurfaceShape(
                topCornerRadius: isExpanded ? AIDrawerMetrics.flareRadius : 5,
                bottomCornerRadius: isExpanded ? 28 : 12
            )
            .frame(
                width: isExpanded ? panelSize.width : AIDrawerMetrics.flareRadius * 2,
                height: isExpanded ? panelSize.height : layout.metrics.bridgeHeight
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .compositingGroup()
        .opacity(isExpanded ? 1 : 0)
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: isExpanded ? 0.28 : 0.22, extraBounce: 0),
            value: isExpanded
        )
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { expandedTaskID = nil }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let message = store.loadErrorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(AITaskStatus.failed.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.tasks) { task in
                            AITaskRow(
                                task: task,
                                isExpanded: expandedTaskID == task.id,
                                actions: actions,
                                onToggle: { toggle(task) }
                            )
                            Divider().overlay(Color.white.opacity(0.07))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
            if progressServer.url != nil, let open = actions.openProgressPage {
                Button(action: open) {
                    Label("Progress page", systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the local progress page in your browser")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("AI")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
            if !store.tasks.isEmpty {
                Text("\(store.tasks.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer(minLength: 8)
            Button(action: actions.newTask) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New AI task")
            .help("New AI task (\(shortcutHint))")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.white.opacity(0.4))
            Text("Hand a todo to Claude")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.85))
            Text("Press \(shortcutHint) from any app. Tasks and their progress appear here.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
    }

    private func toggle(_ task: AITask) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.2, extraBounce: 0)) {
            expandedTaskID = expandedTaskID == task.id ? nil : task.id
        }
    }
}

import SwiftUI

struct AITaskRow: View {
    let task: AITask
    let isExpanded: Bool
    let actions: AIDrawerActions
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var followUpText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    statusIcon
                        .frame(width: 16, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(task.status == .cancelled ? 0.5 : 0.92))
                            .lineLimit(isExpanded ? 3 : 1)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !task.artifactURLs.isEmpty {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(task.title), \(task.status.accessibilityName)")
            .accessibilityValue(subtitle)
            .accessibilityHint(isExpanded ? "Hide details" : "Show details")

            if isExpanded {
                details
                    .padding(.leading, 26)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        let icon = Image(systemName: task.status.symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(task.status.tint)
            .padding(.top, 2)
        if task.status == .running {
            icon
                .opacity(isPulsing && !reduceMotion ? 0.45 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }
        } else {
            icon
        }
    }

    private var subtitle: String {
        switch task.status {
        case .queued: "Queued"
        case .running: task.lastActivity ?? "Working…"
        case .done: task.summary.map { firstLine(of: $0) } ?? "Done"
        case .failed: task.errorMessage.map { firstLine(of: $0) } ?? "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.prompt)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = task.summary, task.status == .done {
                Text(summary)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = task.errorMessage, task.status == .failed {
                Text(error)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(AITaskStatus.failed.tint)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if task.status == .done || task.status == .failed, let followUp = actions.followUp {
                TextField("Follow up…", text: $followUpText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .rounded))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    .onSubmit {
                        let text = followUpText
                        followUpText = ""
                        followUp(task, text)
                    }
                    .accessibilityLabel("Follow up on \(task.title)")
            }

            HStack(spacing: 6) {
                ForEach(task.artifactURLs, id: \.self) { url in
                    if let open = actions.openArtifact {
                        chip("Artifact", systemImage: "arrow.up.right") { open(url) }
                    }
                }
                if task.status == .running || task.status == .queued, let cancel = actions.cancel {
                    chip("Cancel", systemImage: "stop.fill") { cancel(task) }
                }
                if task.status.isFinished && task.status != .done, let retry = actions.retry {
                    chip("Retry", systemImage: "arrow.clockwise") { retry(task) }
                }
                if let reveal = actions.reveal {
                    chip("Folder", systemImage: "folder") { reveal(task) }
                }
            }
        }
    }

    private func chip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Color.white.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }
}

import SwiftUI

struct AICaptureView: View {
    @Bindable var session: AICaptureSession
    let onDismiss: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(height: 30)
                    .accessibilityHidden(true)
                TextField("What should Claude do?", text: $session.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .lineLimit(1...6)
                    .focused($promptFocused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            session.prompt += "\n"
                        } else {
                            submit()
                        }
                        return .handled
                    }
                    .accessibilityLabel("Task for Claude")
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(session.canSubmit ? Color.white : Color.secondary)
                        .background(
                            session.canSubmit ? Color.accentColor : Color.primary.opacity(0.06),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!session.canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Add AI task")
                .help("Add AI task (Return)")
            }

            if let error = session.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Return to add · Shift-Return for a new line · Esc to close · \(session.shortcutHint) toggles this panel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(QuickCaptureSurface())
        // Keep the rounded surface and its soft shadow clear of window bounds.
        .padding(20)
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in
                    onHeightChange(height)
                }
            }
        }
        .onAppear { promptFocused = true }
        .onChange(of: session.presentationID) { _, _ in promptFocused = true }
        .onExitCommand(perform: onDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI task capture")
    }

    private func submit() {
        if session.submit() { onDismiss() }
    }
}

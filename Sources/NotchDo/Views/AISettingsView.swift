import AppKit
import SwiftUI

/// The AI section of Settings: permissions, concurrency, publishing, notifications, the
/// local progress server, and the Claude CLI location.
struct AISettingsView: View {
    let ai: AIServices

    @State private var portText = ""
    @State private var confirmsFullAccess = false
    @State private var confirmsClear = false

    private var settingsStore: AISettingsStore { ai.settingsStore }
    private var settings: AISettings { settingsStore.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI tasks")
                .font(.headline)

            VStack(alignment: .leading, spacing: 5) {
                Picker("Claude may", selection: permissionBinding) {
                    ForEach(AIPermissionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(settings.permissionMode.detail)
                    .font(.callout)
                    .foregroundStyle(settings.permissionMode == .bypassPermissions ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Stepper(
                "Run up to \(settings.maxConcurrent) \(settings.maxConcurrent == 1 ? "task" : "tasks") at once",
                value: concurrencyBinding,
                in: AISettings.maxConcurrentRange
            )

            VStack(alignment: .leading, spacing: 5) {
                Toggle("Publish results as Claude Artifacts", isOn: publishBinding)
                Text("Claude may publish a page for reports and charts. Pages are private to your claude.ai account. Turn this off to keep everything on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Notify when a task finishes", isOn: notifyBinding)

            Divider()

            progressServerSection

            Divider()

            claudeSection

            Divider()

            workspaceSection
        }
        .onAppear { portText = String(settings.serverPort) }
        .confirmationDialog(
            "Allow full access?",
            isPresented: $confirmsFullAccess,
            titleVisibility: .visible
        ) {
            Button("Allow Full Access", role: .destructive) {
                settingsStore.setPermissionMode(.bypassPermissions)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude will be able to run any command and change any file your account can, not just the AI workspace.")
        }
        .confirmationDialog(
            "Delete finished tasks?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Delete \(finishedCount) Finished", role: .destructive) {
                ai.taskStore.removeFinished()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their records, logs, and results are removed. Files Claude created in projects/ are kept.")
        }
    }

    // MARK: - Sections

    private var progressServerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Progress page on this Mac", isOn: serverBinding)
            HStack {
                Text("Port")
                TextField("Port", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit(commitPort)
                    .accessibilityLabel("Progress page port")
                Spacer()
            }
            .disabled(!settings.serverEnabled)
            serverStatus
        }
    }

    @ViewBuilder
    private var serverStatus: some View {
        switch ai.server.state {
        case .running(let port):
            HStack(spacing: 6) {
                Image(systemName: "circle.fill").foregroundStyle(.green).font(.system(size: 7))
                    .accessibilityHidden(true)
                if let url = ai.server.url {
                    Link("127.0.0.1:\(port)", destination: url)
                }
                if port != UInt16(clamping: settings.serverPort) {
                    Text("(preferred port was busy)").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        case .failed(let message):
            Text("Could not start: \(message)")
                .font(.callout)
                .foregroundStyle(.red)
        case .starting:
            Text("Starting…").font(.callout).foregroundStyle(.secondary)
        case .stopped:
            Text("Off. Only this Mac can open the page when it is on.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude CLI")
                TextField("Automatic", text: pathBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Claude CLI path")
            }
            if let found = locatedClaude {
                Text("Using \(found.path)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Claude Code was not found. Install it, or enter the path to the claude executable.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Workspace") {
                Text(ai.workspace.rootURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([ai.workspace.rootURL])
                }
                Button("Delete Finished Tasks…") { confirmsClear = true }
                    .disabled(finishedCount == 0)
            }
        }
    }

    // MARK: - Helpers

    private var finishedCount: Int {
        ai.taskStore.tasks.filter { $0.status.isFinished }.count
    }

    /// Looks only at known install paths; asking the login shell would block the UI.
    private var locatedClaude: URL? {
        ClaudeExecutableLocator(loginShellLookup: { nil }).locate(override: settings.claudePathOverride)
    }

    private func commitPort() {
        if let port = Int(portText.trimmingCharacters(in: .whitespaces)), (1024...65_535).contains(port) {
            settingsStore.setServerPort(port)
        }
        portText = String(settings.serverPort)
    }

    private var permissionBinding: Binding<AIPermissionMode> {
        Binding(
            get: { settings.permissionMode },
            set: { mode in
                if mode == .bypassPermissions {
                    confirmsFullAccess = true
                } else {
                    settingsStore.setPermissionMode(mode)
                }
            }
        )
    }

    private var concurrencyBinding: Binding<Int> {
        Binding(get: { settings.maxConcurrent }, set: { settingsStore.setMaxConcurrent($0) })
    }

    private var publishBinding: Binding<Bool> {
        Binding(get: { settings.publishArtifacts }, set: { settingsStore.setPublishArtifacts($0) })
    }

    private var notifyBinding: Binding<Bool> {
        Binding(get: { settings.notifyOnFinish }, set: { settingsStore.setNotifyOnFinish($0) })
    }

    private var serverBinding: Binding<Bool> {
        Binding(get: { settings.serverEnabled }, set: { settingsStore.setServerEnabled($0) })
    }

    private var pathBinding: Binding<String> {
        Binding(get: { settings.claudePathOverride }, set: { settingsStore.setClaudePathOverride($0) })
    }
}

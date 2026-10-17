import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    let store: RemindersStore
    let globalShortcut: GlobalShortcutStore
    let aiCaptureShortcut: GlobalShortcutStore
    let ai: AIServices
    @State private var launchAtLogin: LaunchAtLoginStore

    @Environment(\.scenePhase) private var scenePhase

    init(
        store: RemindersStore,
        globalShortcut: GlobalShortcutStore,
        aiCaptureShortcut: GlobalShortcutStore,
        ai: AIServices
    ) {
        self.store = store
        self.globalShortcut = globalShortcut
        self.aiCaptureShortcut = aiCaptureShortcut
        self.ai = ai
        #if NOTCHDO_DEMO
        _launchAtLogin = State(initialValue: LaunchAtLoginStore(service: DemoLoginItemService()))
        #else
        _launchAtLogin = State(initialValue: LaunchAtLoginStore())
        #endif
    }

    init(
        store: RemindersStore,
        globalShortcut: GlobalShortcutStore,
        aiCaptureShortcut: GlobalShortcutStore,
        ai: AIServices,
        launchAtLogin: LaunchAtLoginStore
    ) {
        self.store = store
        self.globalShortcut = globalShortcut
        self.aiCaptureShortcut = aiCaptureShortcut
        self.ai = ai
        _launchAtLogin = State(initialValue: launchAtLogin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("NotchDo")
                        .font(.headline)
                    Text("Your reminders, right on the notch.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .disabled(launchAtLogin.state == .unavailable)

                Text(launchAtLogin.state.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if launchAtLogin.state == .requiresApproval {
                    Button("Open Login Items Settings") {
                        launchAtLogin.openSystemSettings()
                    }
                    .accessibilityHint("Opens System Settings to approve NotchDo")
                }

                if let errorMessage = launchAtLogin.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Launch at Login error: \(errorMessage)")
                }
            }

            Divider()

            ShortcutRecorderView(store: globalShortcut)

            ShortcutRecorderView(
                store: aiCaptureShortcut,
                title: "AI task shortcut",
                detail: "Opens the AI task panel from any app so you can hand a todo to Claude."
            )

            Divider()

            AISettingsView(ai: ai)

            Divider()

            LabeledContent("Reminders access") {
                Text(accessText)
                    .foregroundStyle(store.authorization == .fullAccess ? .green : .secondary)
            }

            Text("Reminders are saved directly to Apple Reminders. AI tasks are stored as files in the NotchDo folder on your Desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(versionText)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            launchAtLogin.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                launchAtLogin.refresh()
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isRequested },
            set: { launchAtLogin.setRequested($0) }
        )
    }

    private var accessText: String {
        switch store.authorization {
        case .fullAccess: return "Connected"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .requesting: return "Requesting…"
        case .notDetermined: return "Not requested"
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), .none):
            return "Version \(version)"
        default:
            return "NotchDo"
        }
    }
}

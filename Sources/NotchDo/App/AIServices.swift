import AppKit
import OSLog

/// Composition root for the AI workspace: storage, scheduler, progress server, and
/// notifications. Keeps `AppDelegate` free of AI wiring.
@MainActor
final class AIServices {
    private static let logger = Logger(subsystem: "com.luku.NotchDo", category: "AIServices")

    let workspace = AIWorkspace.appDefault
    let taskStore: AITaskStore
    let settingsStore = AISettingsStore()
    let server: LocalProgressServer
    private(set) var scheduler: AITaskScheduler!
    private let notifier: (any AINotifying)?
    private var appliedServerConfiguration: ServerConfiguration?

    private struct ServerConfiguration: Equatable {
        var enabled: Bool
        var port: Int
    }

    init() {
        let store = AITaskStore(persistence: AITaskFileStore(workspace: workspace))
        taskStore = store
        server = LocalProgressServer(source: StoreProgressDataSource(store: store), workspace: workspace)
        #if NOTCHDO_DEMO
        notifier = nil
        #else
        notifier = AINotifier()
        #endif
        scheduler = makeScheduler()
        store.onTaskAdded = { [weak self] _ in self?.scheduler.pump() }
        scheduler.onTaskFinished = { [weak self] task in self?.taskFinished(task) }
        settingsStore.onChange = { [weak self] in self?.settingsChanged() }
        notifier?.onOpenTask = { [weak self] id in self?.openProgressPage(taskID: id) }
    }

    /// Prepares the workspace, resumes queued work, and starts the progress server.
    func start() {
        do {
            try workspace.bootstrap()
        } catch {
            Self.logger.error("Could not prepare the AI workspace: \(error.localizedDescription, privacy: .public)")
        }
        taskStore.load()
        scheduler.pump()
        reconcileServer()
    }

    func shutdown() {
        scheduler.cancelAll()
        server.stop()
    }

    func openProgressPage(taskID: UUID? = nil) {
        guard var url = server.url else { return }
        if let taskID, let withTask = URL(string: url.absoluteString + "#" + taskID.uuidString) { url = withTask }
        NSWorkspace.shared.open(url)
    }

    func makeDrawerActions() -> AIDrawerActions {
        var actions = AIDrawerActions()
        actions.cancel = { [scheduler] task in scheduler?.cancel(task.id) }
        actions.retry = { [scheduler] task in scheduler?.retry(task.id) }
        actions.followUp = { [scheduler] task, text in scheduler?.followUp(task.id, prompt: text) }
        actions.newTask = { AppActions.requestAICapture() }
        actions.openArtifact = { NSWorkspace.shared.open($0) }
        actions.openProgressPage = { [weak self] in self?.openProgressPage() }
        actions.reveal = { [workspace] task in
            NSWorkspace.shared.activateFileViewerSelecting([workspace.taskURL(id: task.id)])
        }
        return actions
    }

    private func makeScheduler() -> AITaskScheduler {
        #if NOTCHDO_DEMO
        let runner: any ClaudeRunning = DemoClaudeRunner()
        let locate: (String) -> URL? = { _ in URL(filePath: "/usr/bin/true") }
        #else
        let runner: any ClaudeRunning = ClaudeProcessRunner()
        let locator = ClaudeExecutableLocator()
        let locate: (String) -> URL? = { locator.locate(override: $0) }
        #endif
        return AITaskScheduler(
            store: taskStore,
            runner: runner,
            workspace: workspace,
            settings: { [settingsStore] in settingsStore.settings },
            locateClaude: locate
        )
    }

    private func taskFinished(_ task: AITask) {
        if settingsStore.settings.notifyOnFinish { notifier?.notifyFinished(task) }
    }

    private func settingsChanged() {
        scheduler.pump()
        reconcileServer()
    }

    private func reconcileServer() {
        let settings = settingsStore.settings
        let wanted = ServerConfiguration(enabled: settings.serverEnabled, port: settings.serverPort)
        guard wanted != appliedServerConfiguration else { return }
        appliedServerConfiguration = wanted
        if wanted.enabled {
            server.start(preferredPort: wanted.port)
        } else {
            server.stop()
        }
    }
}

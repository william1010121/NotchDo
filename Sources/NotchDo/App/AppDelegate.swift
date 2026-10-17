import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let remindersStore = RemindersStore()
    let globalShortcutStore = GlobalShortcutStore()
    let aiCaptureShortcutStore = GlobalShortcutStore.aiCapture()
    let ai = AIServices()
    private var panelController: NotchPanelController?
    private var quickCapturePanelController: QuickCapturePanelController?
    private var aiCapturePanelController: AICapturePanelController?
    private var quickCaptureRequestObserver: NSObjectProtocol?
    private var aiCaptureRequestObserver: NSObjectProtocol?

    override init() {
        super.init()
        globalShortcutStore.siblingShortcut = { [aiCaptureShortcutStore] in aiCaptureShortcutStore.shortcut }
        aiCaptureShortcutStore.siblingShortcut = { [globalShortcutStore] in globalShortcutStore.shortcut }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ai.start()

        let panelController = NotchPanelController(
            store: remindersStore,
            aiStore: ai.taskStore,
            progressServer: ai.server,
            aiShortcutHint: { [aiCaptureShortcutStore] in aiCaptureShortcutStore.shortcut.displayName },
            aiActions: ai.makeDrawerActions()
        )
        self.panelController = panelController
        panelController.show()

        let quickCapturePanelController = QuickCapturePanelController(store: remindersStore)
        self.quickCapturePanelController = quickCapturePanelController
        globalShortcutStore.onPerformShortcut = { [weak quickCapturePanelController] in
            quickCapturePanelController?.toggle()
        }
        quickCaptureRequestObserver = NotificationCenter.default.addObserver(
            forName: AppActions.quickCaptureRequested,
            object: nil,
            queue: .main
        ) { [weak quickCapturePanelController] _ in
            Task { @MainActor in quickCapturePanelController?.show() }
        }

        let aiCapturePanelController = AICapturePanelController(
            store: ai.taskStore,
            shortcutHint: { [aiCaptureShortcutStore] in aiCaptureShortcutStore.shortcut.displayName }
        )
        self.aiCapturePanelController = aiCapturePanelController
        aiCaptureShortcutStore.onPerformShortcut = { [weak aiCapturePanelController] in
            aiCapturePanelController?.toggle()
        }
        aiCaptureRequestObserver = NotificationCenter.default.addObserver(
            forName: AppActions.aiCaptureRequested,
            object: nil,
            queue: .main
        ) { [weak aiCapturePanelController] _ in
            Task { @MainActor in aiCapturePanelController?.show() }
        }

        Task {
            await remindersStore.start()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task {
            await remindersStore.refreshAuthorization()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ai.shutdown()
        if let quickCaptureRequestObserver {
            NotificationCenter.default.removeObserver(quickCaptureRequestObserver)
        }
        if let aiCaptureRequestObserver {
            NotificationCenter.default.removeObserver(aiCaptureRequestObserver)
        }
    }
}

import AppKit
import SwiftUI

/// Owns the second fixed panel that sits to the right of the expanded notch panel.
/// AppKit is required for the same reason as `NotchPanelController`: a borderless,
/// non-activating surface above the menu bar that SwiftUI scenes cannot create.
@MainActor
final class AIDrawerPanelController {
    private let layout: NotchLayoutModel
    private let panel: NotchPanel

    init(
        store: AITaskStore,
        progressServer: LocalProgressServer,
        layout: NotchLayoutModel,
        interaction: NotchInteractionModel,
        shortcutHint: @escaping () -> String,
        actions: AIDrawerActions,
        mainFrame: CGRect
    ) {
        self.layout = layout
        let frame = AIDrawerMetrics.frame(besideMainPanel: mainFrame)
        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(
            rootView: AIDrawerView(
                store: store,
                progressServer: progressServer,
                layout: layout,
                interaction: interaction,
                shortcutHint: shortcutHint(),
                actions: actions
            )
        )
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        panel.contentView = hostingView
        self.panel = panel
    }

    var frame: CGRect { panel.frame }

    func show() {
        panel.orderFrontRegardless()
    }

    func setExpanded(_ expanded: Bool) {
        panel.ignoresMouseEvents = !expanded
    }

    func reposition(besideMainPanel mainFrame: CGRect) {
        panel.setFrame(AIDrawerMetrics.frame(besideMainPanel: mainFrame), display: true)
    }
}

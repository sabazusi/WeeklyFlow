import AppKit
import SwiftData
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainPanel: MenuBarPanel?
    private var modelContainer: ModelContainer?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            modelContainer = try ModelContainer(for: TaskItem.self)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "タスクデータを開けませんでした"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "WeeklyFlowを開く")
        item.button?.toolTip = "WeeklyFlowを開く"
        item.button?.target = self
        item.button?.action = #selector(toggleMainPanel)
        statusItem = item
    }

    @objc private func toggleMainPanel() {
        guard let modelContainer, let button = statusItem?.button else { return }

        if let mainPanel, mainPanel.isVisible && NSApp.isActive {
            mainPanel.orderOut(nil)
            return
        }

        if mainPanel == nil {
            let rootView = MainView()
                .modelContainer(modelContainer)
                .background(Color(nsColor: .windowBackgroundColor))
            let panel = MenuBarPanel(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = NSHostingController(rootView: rootView)
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.cornerRadius = 12
            panel.contentView?.layer?.masksToBounds = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            mainPanel = panel
        }

        guard let panel = mainPanel else { return }
        position(panel, below: button)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func position(_ panel: NSPanel, below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let height = panel.frame.height
        let x = min(max(buttonFrame.midX - width / 2, visible.minX), visible.maxX - width)
        let y = max(min(buttonFrame.minY - height - 6, visible.maxY - height), visible.minY)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

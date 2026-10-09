import AppKit
import SwiftData
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKeyManager: GlobalHotKeyManager?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "WeeklyFlowを開く")
        item.button?.toolTip = "WeeklyFlowを開く"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        let manager = GlobalHotKeyManager { [weak self] in self?.togglePopover() }
        hotKeyManager = manager

        let content: AnyView
        do {
            let container = try ModelContainer(for: TaskItem.self)
            content = AnyView(MainView(hotKeyManager: manager).modelContainer(container))
        } catch {
            content = AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    Text("タスクデータを開けませんでした").font(.headline)
                    Text(error.localizedDescription).foregroundStyle(.secondary)
                    Button("終了") { NSApp.terminate(nil) }
                }
                .padding(20)
            )
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 780, height: 560)
        popover.contentViewController = NSHostingController(rootView: content)
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }
}

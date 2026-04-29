import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var configManager: ConfigManager!
    private var dragDetector: DragDetector!
    private var overlayController: ZoneOverlayController!
    private var preferencesController: PreferencesWindowController?
    var currentConfig: ScreenDividerConfig?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Only quit if the user explicitly chose Quit from the menu
        // This prevents macOS from auto-killing us when windows close
        return .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button { button.title = "SD" }

        DispatchQueue.main.async { [self] in
            let trusted = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            if !trusted { NSLog("ScreenDivider: Accessibility permission required.") }

            let testMask: CGEventMask = 1 << CGEventType.mouseMoved.rawValue
            if let testTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                                options: .listenOnly, eventsOfInterest: testMask,
                                                callback: { _, _, e, _ in Unmanaged.passUnretained(e) },
                                                userInfo: nil) {
                CFMachPortInvalidate(testTap)
            } else {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Input Monitoring Permission Needed"
                    alert.informativeText = "Screen Divider needs Input Monitoring to detect window drags.\n\nSystem Settings > Privacy & Security > Input Monitoring"
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                    }
                }
            }

            if let img = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Screen Divider") {
                img.size = NSSize(width: 18, height: 18)
                statusItem.button?.image = img
                statusItem.button?.title = ""
            }

            configManager = ConfigManager()
            configManager.ensureConfigOnFirstLaunch()
            overlayController = ZoneOverlayController()
            dragDetector = DragDetector()

            currentConfig = configManager.load()
            setupDragDetector()
            dragDetector.start()
            statusItem.menu = buildMenu()

            configManager.onConfigReloaded = { [weak self] config in
                self?.currentConfig = config
                self?.statusItem.menu = self?.buildMenu()
            }
            configManager.startWatching()
        }
    }

    private func setupDragDetector() {
        dragDetector.onDragStarted = { [weak self] _ in
            guard let config = self?.currentConfig else { return }
            self?.overlayController.showOverlays(for: config)
        }
        dragDetector.onDragMoved = { [weak self] pos in
            self?.overlayController.updateHover(cursorPosition: pos)
        }
        dragDetector.onDragEnded = { [weak self] pos, window in
            if let match = self?.overlayController.snapRectAtPoint(pos) {
                WindowManager.shared.snapWindow(window, to: match.rect)
            }
            self?.overlayController.hideOverlays()
        }
        dragDetector.onDragCancelled = { [weak self] in
            self?.overlayController.hideOverlays()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let config = currentConfig {
            for layout in config.screens {
                let count = layout.root.zoneCount
                let item = NSMenuItem(title: "\(layout.screenName) — \(count) zones", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let dragItem = NSMenuItem(title: "Drag to Snap", action: #selector(toggleDrag(_:)), keyEquivalent: "")
        dragItem.target = self
        dragItem.state = (dragDetector?.isEnabled ?? true) ? .on : .off
        menu.addItem(dragItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Edit Layouts...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemManager.shared.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func toggleDrag(_ sender: NSMenuItem) {
        dragDetector.isEnabled.toggle()
        sender.state = dragDetector.isEnabled ? .on : .off
    }

    @objc private func openPreferences() {
        if let existing = preferencesController {
            existing.showWindow()
            return
        }

        let config = configManager.load() ?? ScreenDividerConfig(screens: [])
        let controller = PreferencesWindowController(
            configManager: configManager, config: config,
            onConfigChanged: { [weak self] config in
                // Apply immediately — no need to wait for file watcher
                self?.currentConfig = config
                self?.statusItem.menu = self?.buildMenu()
            })
        controller.willOpen = { [weak self] in self?.dragDetector.isEnabled = false }
        controller.didClose = { [weak self] in
            self?.dragDetector.isEnabled = true
            // Don't nil out preferencesController here — it gets reused
        }
        preferencesController = controller
        controller.showWindow()
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let mgr = LoginItemManager.shared
        mgr.setEnabled(!mgr.isEnabled)
        sender.state = mgr.isEnabled ? .on : .off
    }
}

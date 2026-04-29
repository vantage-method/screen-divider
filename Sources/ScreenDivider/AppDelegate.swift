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

        // Set app icon (shown in preferences window, Force Quit, Activity Monitor, Finder)
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let resourceDir = execURL.deletingLastPathComponent().appendingPathComponent("Resources")
        for name in ["AppIcon.icns", "app-icon@2x.png", "app-icon.png"] {
            let url = resourceDir.appendingPathComponent(name)
            if let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
                break
            }
        }

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

            if let iconImage = loadMenuBarIcon() {
                iconImage.isTemplate = true
                statusItem.button?.image = iconImage
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

    private func loadMenuBarIcon() -> NSImage? {
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let resourceDir = execURL.deletingLastPathComponent().appendingPathComponent("Resources")
        let bundleResourceDir = Bundle.main.resourceURL

        // Build a multi-representation image for crisp rendering on all displays
        let img = NSImage(size: NSSize(width: 16, height: 16))
        var added = false

        for (suffix, scale) in [("", 1), ("@2x", 2), ("@3x", 3)] {
            let filename = "menubar-icon\(suffix).png"
            // Check bundle first, then relative path
            let candidates = [
                bundleResourceDir?.appendingPathComponent(filename),
                resourceDir.appendingPathComponent(filename)
            ].compactMap { $0 }

            for url in candidates {
                if let rep = NSImageRep(contentsOf: url) {
                    rep.size = NSSize(width: 16, height: 16)
                    rep.pixelsWide = 18 * scale
                    rep.pixelsHigh = 18 * scale
                    img.addRepresentation(rep)
                    added = true
                    break
                }
            }
        }

        if added { return img }

        // Fallback to SF Symbol
        let fallback = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Screen Divider")
        fallback?.size = NSSize(width: 16, height: 16)
        return fallback
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
            for (index, layout) in config.screens.enumerated() {
                let count = layout.root.zoneCount
                let item = NSMenuItem(title: "\(layout.screenName) — \(count) zones", action: #selector(openPreferencesForScreen(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
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

    @objc private func openPreferencesForScreen(_ sender: NSMenuItem) {
        showPreferences(selectScreenIndex: sender.tag)
    }

    @objc private func openPreferences() {
        showPreferences(selectScreenIndex: nil)
    }

    private func showPreferences(selectScreenIndex: Int?) {
        // Determine which screen to select: explicit choice, or auto-detect from mouse location
        let screenIndex: Int
        if let explicit = selectScreenIndex {
            screenIndex = explicit
        } else if let config = currentConfig {
            let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            let mouseName = mouseScreen?.localizedName ?? NSScreen.main?.localizedName ?? ""
            screenIndex = config.screens.firstIndex(where: { $0.screenName == mouseName }) ?? 0
        } else {
            screenIndex = 0
        }

        if let existing = preferencesController {
            existing.refreshConfig(configManager.load() ?? ScreenDividerConfig(screens: []))
            existing.showWindow(selectScreenIndex: screenIndex)
            return
        }

        let config = configManager.load() ?? ScreenDividerConfig(screens: [])
        let controller = PreferencesWindowController(
            configManager: configManager, config: config,
            onConfigChanged: { [weak self] config in
                self?.currentConfig = config
                self?.statusItem.menu = self?.buildMenu()
            })
        controller.willOpen = { [weak self] in self?.dragDetector.isEnabled = false }
        controller.didClose = { [weak self] in
            self?.dragDetector.isEnabled = true
        }
        preferencesController = controller
        controller.showWindow(selectScreenIndex: screenIndex)
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let mgr = LoginItemManager.shared
        mgr.setEnabled(!mgr.isEnabled)
        sender.state = mgr.isEnabled ? .on : .off
    }
}

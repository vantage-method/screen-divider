import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var configManager: ConfigManager!
    private var dragDetector: DragDetector!
    private var overlayController: ZoneOverlayController!
    private var preferencesController: PreferencesWindowController?
    private var paywallController: PaywallWindowController?
    var currentConfig: ScreenDividerConfig?
    private var permissionCheckTimer: Timer?
    /// The user's own on/off toggle; actual detection also requires an
    /// active subscription (see applyDragGate).
    private var dragUserEnabled = true
    private var hasShownLaunchPaywall = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    // MARK: - Permission checks

    private var hasAccessibility: Bool {
        return AXIsProcessTrusted()
    }

    private var allPermissionsGranted: Bool {
        return hasAccessibility
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Set app icon
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

            // Subscription state drives whether snapping is active
            SubscriptionManager.shared.onStatusRefreshed = { [weak self] subscribed in
                guard let self = self else { return }
                self.applyDragGate()
                self.statusItem.menu = self.buildMenu()
                if subscribed {
                    self.paywallController?.close()
                } else if !self.hasShownLaunchPaywall {
                    self.hasShownLaunchPaywall = true
                    self.showPaywall()
                }
            }
            SubscriptionManager.shared.start()
            applyDragGate()

            // Trigger the native macOS accessibility prompt
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

            // Periodically check permissions; restart drag detector once granted
            var wasGranted = hasAccessibility
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let nowGranted = self.hasAccessibility
                if nowGranted && !wasGranted {
                    // Permission was just granted — restart the drag detector
                    // so NSEvent monitors are created with the new permission
                    NSLog("ScreenDivider: Accessibility granted — restarting drag detector")
                    self.dragDetector.stop()
                    self.dragDetector.start()
                    wasGranted = true
                }
                self.statusItem.menu = self.buildMenu()
            }
        }
    }

    // MARK: - Permissions

    // MARK: - Menu bar icon

    private func loadMenuBarIcon() -> NSImage? {
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let resourceDir = execURL.deletingLastPathComponent().appendingPathComponent("Resources")
        let bundleResourceDir = Bundle.main.resourceURL

        let img = NSImage(size: NSSize(width: 16, height: 16))
        var added = false

        for (suffix, scale) in [("", 1), ("@2x", 2), ("@3x", 3)] {
            let filename = "menubar-icon\(suffix).png"
            let candidates = [
                bundleResourceDir?.appendingPathComponent(filename),
                resourceDir.appendingPathComponent(filename)
            ].compactMap { $0 }

            for url in candidates {
                if let rep = NSImageRep(contentsOf: url) {
                    rep.size = NSSize(width: 16, height: 16)
                    rep.pixelsWide = 16 * scale
                    rep.pixelsHigh = 16 * scale
                    img.addRepresentation(rep)
                    added = true
                    break
                }
            }
        }

        if added { return img }

        let fallback = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Screen Divider")
        fallback?.size = NSSize(width: 16, height: 16)
        return fallback
    }

    // MARK: - Drag detection

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

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Permission status at the top if something is missing
        let accOK = hasAccessibility

        if !accOK {
            let item = NSMenuItem(title: "Grant Accessibility...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if SubscriptionManager.shared.statusKnown && !SubscriptionManager.shared.isSubscribed {
            let item = NSMenuItem(title: "Unlock Screen Divider...", action: #selector(showPaywallAction), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        // Screen layouts
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

        let permItem = NSMenuItem(title: "Permissions...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        if SubscriptionManager.shared.isSubscribed {
            let subItem = NSMenuItem(title: "Manage Subscription...", action: #selector(openManageSubscription), keyEquivalent: "")
            subItem.target = self
            menu.addItem(subItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    // MARK: - Actions

    @objc private func toggleDrag(_ sender: NSMenuItem) {
        guard SubscriptionManager.shared.isSubscribed else {
            showPaywall()
            return
        }
        dragUserEnabled.toggle()
        applyDragGate()
        sender.state = dragDetector.isEnabled ? .on : .off
    }

    /// Snapping runs only when the user has it on AND a subscription is active.
    private func applyDragGate() {
        dragDetector.isEnabled = dragUserEnabled && SubscriptionManager.shared.isSubscribed
    }

    @objc private func showPaywallAction() {
        showPaywall()
    }

    private func showPaywall() {
        if paywallController == nil {
            let controller = PaywallWindowController()
            controller.onUnlocked = { [weak self] in
                self?.applyDragGate()
                self?.statusItem.menu = self?.buildMenu()
            }
            paywallController = controller
        }
        paywallController?.show()
    }

    @objc private func openManageSubscription() {
        NSWorkspace.shared.open(URL(string: "https://apps.apple.com/account/subscriptions")!)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }


    @objc private func openPreferencesForScreen(_ sender: NSMenuItem) {
        showPreferences(selectScreenIndex: sender.tag)
    }

    @objc private func openPreferences() {
        showPreferences(selectScreenIndex: nil)
    }

    private func showPreferences(selectScreenIndex: Int?) {
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
            self?.applyDragGate()
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

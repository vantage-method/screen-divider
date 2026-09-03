import AppKit
import ApplicationServices
import UserNotifications

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
    /// Commits behind upstream, discovered by the silent launch check.
    private var pendingUpdateCount = 0
    private var isUpdating = false
    private var updateCheckTimer: Timer?
    /// Upstream commit we last nudged about, so we don't renotify each cycle.
    private var lastNotifiedLatest = ""
    private let updateCheckInterval: TimeInterval = 6 * 3600

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

            // Silent update check on launch + periodically (dev builds from a clone).
            startUpdateChecks()

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
                let count = layout.zoneRects.count
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

        if UpdateManager.shared.canSelfUpdate {
            let title = pendingUpdateCount > 0
                ? "Install Update (\(pendingUpdateCount) new)..."
                : "Check for Updates..."
            let updateItem = NSMenuItem(title: title, action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
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

    // MARK: - Updates

    /// Check on launch, then re-check on a timer so the app nudges you when an
    /// update lands without you having to open the menu.
    private func startUpdateChecks() {
        guard UpdateManager.shared.canSelfUpdate else { return }
        performSilentUpdateCheck()
        updateCheckTimer?.invalidate()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: updateCheckInterval, repeats: true) { [weak self] _ in
            self?.performSilentUpdateCheck()
        }
    }

    /// Quiet check: refreshes the menu, and posts a (provisional, no-prompt)
    /// notification the first time a given upstream commit becomes available.
    private func performSilentUpdateCheck() {
        guard UpdateManager.shared.canSelfUpdate, !isUpdating else { return }
        UpdateManager.shared.check { [weak self] result in
            guard let self = self, case .success(let status) = result else { return }
            self.pendingUpdateCount = status.behind
            self.statusItem.menu = self.buildMenu()
            if status.behind > 0, status.latestShort != self.lastNotifiedLatest {
                self.lastNotifiedLatest = status.latestShort
                self.postUpdateNotification(count: status.behind)
            } else if status.behind == 0 {
                self.lastNotifiedLatest = ""
                UNUserNotificationCenter.current()
                    .removeDeliveredNotifications(withIdentifiers: ["sd.update.available"])
            }
        }
    }

    /// Provisional authorization delivers quietly to Notification Center with no
    /// permission dialog; the menu-bar item is the always-present fallback.
    private func postUpdateNotification(count: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.provisional, .alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Screen Divider Update Available"
            content.body = "\(count) new change\(count == 1 ? "" : "s"). Open the menu bar icon to install."
            let request = UNNotificationRequest(identifier: "sd.update.available", content: content, trigger: nil)
            center.add(request)
        }
    }

    /// Menu action: fetch, and if behind, offer to install and relaunch.
    @objc private func checkForUpdates() {
        guard !isUpdating else { return }
        UpdateManager.shared.check { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.showUpdateAlert(title: "Couldn't Check for Updates",
                                     text: error.localizedDescription, style: .warning)
            case .success(let status):
                self.pendingUpdateCount = status.behind
                self.statusItem.menu = self.buildMenu()
                if status.behind <= 0 {
                    self.showUpdateAlert(title: "You're Up to Date",
                                         text: "Screen Divider is running the latest version.", style: .informational)
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Update Available"
                alert.informativeText = "\(status.behind) new change\(status.behind == 1 ? "" : "s") on \(status.branch). Install now and relaunch?"
                alert.addButton(withTitle: "Install & Relaunch")
                alert.addButton(withTitle: "Later")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                self.runUpdate()
            }
        }
    }

    private func runUpdate() {
        isUpdating = true
        let progress = NSAlert()
        progress.messageText = "Updating Screen Divider"
        progress.informativeText = "Starting…"
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        progress.accessoryView = spinner
        // Show as a non-blocking panel so we can update its text as we go.
        let panel = progress.window
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        UpdateManager.shared.performUpdate(progress: { msg in
            progress.informativeText = msg
        }, done: { [weak self] result in
            guard let self = self else { return }
            panel.orderOut(nil)
            self.isUpdating = false
            switch result {
            case .success:
                // The new build is installed; the relaunch helper will reopen
                // it after we quit.
                NSApp.terminate(nil)
            case .failure(let error):
                self.showUpdateAlert(title: "Update Failed",
                                     text: error.localizedDescription + "\n\nYou can update manually with ./install.sh.",
                                     style: .critical)
            }
        })
    }

    private func showUpdateAlert(title: String, text: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

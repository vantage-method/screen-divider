import AppKit
import ApplicationServices

class SetupWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow!
    private var statusLabel: NSTextField!
    private var actionBtn: NSButton!
    private var timer: Timer?
    var onAllGranted: (() -> Void)?

    func show() {
        if window != nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            updateStatus()
            return
        }
        buildWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateStatus()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Screen Divider Setup"
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true

        let content = window.contentView!
        let m: CGFloat = 30

        let title = NSTextField(labelWithString: "Screen Divider needs your permission")
        title.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)

        let subtitle = NSTextField(wrappingLabelWithString: "macOS requires you to grant Accessibility and Input Monitoring so Screen Divider can detect window drags and snap them into zones.\n\nClick the button below — it will open the right settings page. Find \"Screen Divider\" in the list and toggle it on.")
        subtitle.font = NSFont.systemFont(ofSize: 12.5)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subtitle)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        actionBtn = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        actionBtn.bezelStyle = .rounded
        actionBtn.controlSize = .large
        actionBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        actionBtn.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(actionBtn)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: m),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            subtitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),
            subtitle.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),

            actionBtn.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -m),
            actionBtn.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: m),

            statusLabel.centerYAnchor.constraint(equalTo: actionBtn.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -m),
        ])
    }

    private func updateStatus() {
        let accOK = AXIsProcessTrusted()
        let inputOK = testEventTapReceivesEvents()

        if accOK && inputOK {
            statusLabel.stringValue = "All set!"
            statusLabel.textColor = NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)
            actionBtn.title = "Done"
            actionBtn.action = #selector(closeWindow)
            timer?.invalidate()
            timer = nil
            onAllGranted?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.window?.close()
            }
        } else if !accOK {
            statusLabel.stringValue = "Accessibility: required"
            statusLabel.textColor = .systemOrange
            actionBtn.title = "Open Accessibility Settings"
            actionBtn.action = #selector(openAccessibility)
        } else {
            statusLabel.stringValue = "Input Monitoring: required"
            statusLabel.textColor = .systemOrange
            actionBtn.title = "Open Input Monitoring Settings"
            actionBtn.action = #selector(openInputMonitoring)
        }
    }

    private func testEventTapReceivesEvents() -> Bool {
        // On macOS 13+, tap creation always succeeds but events are silently dropped.
        // We can't truly test if events flow without waiting for user interaction.
        // Use tap creation as a basic check; the real validation happens when
        // the drag detector actually receives events.
        let testMask: CGEventMask = 1 << CGEventType.mouseMoved.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .listenOnly, eventsOfInterest: testMask,
                                           callback: { _, _, e, _ in Unmanaged.passUnretained(e) },
                                           userInfo: nil) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    @objc private func openSettings() {
        let accOK = AXIsProcessTrusted()
        if !accOK {
            openAccessibility()
        } else {
            openInputMonitoring()
        }
    }

    @objc private func openAccessibility() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }
}

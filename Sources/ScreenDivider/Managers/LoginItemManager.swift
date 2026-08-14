import Foundation
import AppKit
import ServiceManagement

class LoginItemManager {
    static let shared = LoginItemManager()

    private let launchAgentLabel = "com.screendivider.app"
    private var legacyLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    /// SMAppService only works from a real .app bundle; `swift build` dev
    /// runs fall back to the legacy launch-agent plist. The App Store build
    /// is sandboxed, so writing to ~/Library/LaunchAgents is not an option
    /// there anyway.
    private var canUseAppService: Bool {
        if #available(macOS 13.0, *) {
            return Bundle.main.bundlePath.hasSuffix(".app")
        }
        return false
    }

    var isEnabled: Bool {
        if #available(macOS 13.0, *), canUseAppService {
            return SMAppService.mainApp.status == .enabled
        }
        return FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *), canUseAppService {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("ScreenDivider: Failed to update login item: \(error)")
            }
            // Clean up any agent left behind by the pre-App Store DMG build
            // (no-op under sandbox, where this path is out of reach).
            try? FileManager.default.removeItem(at: legacyLaunchAgentURL)
            return
        }

        if enabled {
            createLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }

    // MARK: - Legacy launch agent (dev builds only)

    private func createLaunchAgent() {
        let executablePath = ProcessInfo.processInfo.arguments[0]

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let dir = legacyLaunchAgentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: legacyLaunchAgentURL)
            print("ScreenDivider: Launch agent created at \(legacyLaunchAgentURL.path)")
        } catch {
            print("ScreenDivider: Failed to create launch agent: \(error)")
        }
    }

    private func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: legacyLaunchAgentURL)
        print("ScreenDivider: Launch agent removed")
    }
}

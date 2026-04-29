import Foundation
import AppKit

class LoginItemManager {
    static let shared = LoginItemManager()

    private let launchAgentLabel = "com.screendivider.app"
    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            createLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }

    private func createLaunchAgent() {
        // Use the actual binary path (works whether run as .app bundle or standalone)
        let executablePath = ProcessInfo.processInfo.arguments[0]

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let dir = launchAgentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL)
            print("ScreenDivider: Launch agent created at \(launchAgentURL.path)")
        } catch {
            print("ScreenDivider: Failed to create launch agent: \(error)")
        }
    }

    private func removeLaunchAgent() {
        try? FileManager.default.removeItem(at: launchAgentURL)
        print("ScreenDivider: Launch agent removed")
    }
}

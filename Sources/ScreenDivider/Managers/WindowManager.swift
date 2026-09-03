import AppKit
import ApplicationServices

class WindowManager {
    static let shared = WindowManager()

    func snapFocusedWindow(to rect: CGRect) {
        guard let window = getFrontmostWindow() else {
            print("ScreenDivider: Could not get frontmost window")
            return
        }
        setWindowFrame(window, frame: rect)
    }

    func snapWindow(_ window: AXUIElement, to rect: CGRect) {
        setWindowFrame(window, frame: rect)
    }

    private func getFrontmostWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appResult == .success, let app = focusedApp else {
            return nil
        }

        var focusedWindow: AnyObject?
        let winResult = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard winResult == .success else {
            return nil
        }

        return (focusedWindow as! AXUIElement)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)

        // Some apps (Chromium/Electron: Chrome, VS Code, Slack, …) ignore AX
        // size changes while AXEnhancedUserInterface is enabled on the owning
        // app — the window moves but never resizes. Temporarily disable it,
        // apply the frame, then restore it.
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app: AXUIElement? = pid != 0 ? AXUIElementCreateApplication(pid) : nil
        var restoreEnhanced = false
        if let app = app {
            var current: AnyObject?
            if AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &current) == .success,
               (current as? Bool) == true {
                restoreEnhanced = true
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
        }

        // size → position → size is the most reliable order across apps:
        // the first size frees the window from its current bounds so the
        // position can land, and the second corrects any clamping. Apps like
        // Terminal resize in character-grid increments, so the final size may
        // differ slightly; the position set keeps the top-left pinned.
        let setSize: () -> Void = {
            if let v = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
            }
        }
        let setPosition: () -> Void = {
            if let v = AXValueCreate(.cgPoint, &position) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
        }
        setSize()
        setPosition()
        setSize()

        if restoreEnhanced, let app = app {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }
}

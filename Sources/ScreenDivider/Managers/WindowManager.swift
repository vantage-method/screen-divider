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

        // AppleScript/AX automation leaves AXEnhancedUserInterface set on an
        // app, and while it's set AppKit animates frame changes and silently
        // drops programmatic resizes (windows move but keep their size).
        // Clear it around the frame change and restore it afterwards — the
        // same workaround Rectangle and yabai use.
        let enhancedUIAttr = "AXEnhancedUserInterface" as CFString
        var appPid: pid_t = 0
        AXUIElementGetPid(window, &appPid)
        let app = AXUIElementCreateApplication(appPid)
        var euiValue: AnyObject?
        let hadEnhancedUI = AXUIElementCopyAttributeValue(app, enhancedUIAttr, &euiValue) == .success
            && (euiValue as? Bool ?? false)
        if hadEnhancedUI {
            AXUIElementSetAttributeValue(app, enhancedUIAttr, kCFBooleanFalse)
        }

        // Set position first, then size, then position again.
        // Apps like Terminal resize in character-grid increments, so the
        // actual size may differ from what we request. Re-setting position
        // ensures the top-left corner stays pinned to the zone edge.
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        // Retry once if the size didn't take (some apps ignore the first set)
        if let actual = getWindowSize(window),
           abs(actual.width - size.width) > 2 || abs(actual.height - size.height) > 2,
           let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        // Re-pin position after size adjustment
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }

        if hadEnhancedUI {
            AXUIElementSetAttributeValue(app, enhancedUIAttr, kCFBooleanTrue)
        }
    }

    private func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return size
    }
}

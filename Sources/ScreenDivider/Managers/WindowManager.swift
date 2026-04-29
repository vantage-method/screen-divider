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
        // Re-pin position after size adjustment
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }
}

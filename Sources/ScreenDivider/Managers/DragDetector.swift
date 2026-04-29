import AppKit
import ApplicationServices

class DragDetector {
    var onDragStarted: ((_ window: AXUIElement) -> Void)?
    var onDragMoved: ((_ cursorPosition: CGPoint) -> Void)?
    var onDragEnded: ((_ cursorPosition: CGPoint, _ window: AXUIElement) -> Void)?
    var onDragCancelled: (() -> Void)?
    var isEnabled: Bool = true

    private var mouseDownMonitor: Any?
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?

    private var dragState: DragState = .idle
    private var trackedWindow: AXUIElement?
    private var lastWindowPosition: CGPoint = .zero
    private var mouseDownPoint: CGPoint = .zero
    private var dragCheckCount: Int = 0

    private enum DragState {
        case idle
        case watching
        case dragging
    }

    func start() {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event: event, ownPID: ownPID)
        }

        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleMouseDragged(event: event)
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event: event)
        }

        NSLog("ScreenDivider: Drag detector started")
    }

    func stop() {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseDragMonitor { NSEvent.removeMonitor(m) }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m) }
        mouseDownMonitor = nil
        mouseDragMonitor = nil
        mouseUpMonitor = nil
        dragState = .idle
    }

    // MARK: - Event handlers

    private func handleMouseDown(event: NSEvent, ownPID: Int32) {
        guard isEnabled else { return }

        dragState = .idle
        trackedWindow = nil
        dragCheckCount = 0

        // NSEvent gives us screen coordinates (flipped); convert to CG coordinates
        let nsLoc = NSEvent.mouseLocation
        let cgLoc = cgPoint(from: nsLoc)
        mouseDownPoint = cgLoc

        // Try to get the window being clicked
        if let w = getWindowAtPosition(cgLoc), !isOwnWindow(w, ownPID: ownPID),
           let pos = getWindowPosition(w) {
            trackedWindow = w
            lastWindowPosition = pos
            dragState = .watching
        } else if let w = getFocusedWindow(), !isOwnWindow(w, ownPID: ownPID),
                  let pos = getWindowPosition(w) {
            trackedWindow = w
            lastWindowPosition = pos
            dragState = .watching
        }
    }

    private func handleMouseDragged(event: NSEvent) {
        guard isEnabled, dragState != .idle, let window = trackedWindow else { return }

        let nsLoc = NSEvent.mouseLocation
        let loc = cgPoint(from: nsLoc)

        if dragState == .watching {
            dragCheckCount += 1
            if dragCheckCount % 2 != 0 { return }

            let dx = loc.x - mouseDownPoint.x
            let dy = loc.y - mouseDownPoint.y
            guard sqrt(dx*dx + dy*dy) > 6 else { return }

            guard let currentPos = getWindowPosition(window) else {
                dragState = .idle
                return
            }
            let wdx = currentPos.x - lastWindowPosition.x
            let wdy = currentPos.y - lastWindowPosition.y
            if sqrt(wdx*wdx + wdy*wdy) > 3 {
                dragState = .dragging
                onDragStarted?(window)
            } else if dragCheckCount > 15 {
                dragState = .idle
                trackedWindow = nil
            }
        }

        if dragState == .dragging {
            onDragMoved?(loc)
        }
    }

    private func handleMouseUp(event: NSEvent) {
        guard isEnabled else { return }

        let nsLoc = NSEvent.mouseLocation
        let loc = cgPoint(from: nsLoc)

        if dragState == .dragging, let window = trackedWindow {
            onDragEnded?(loc, window)
        } else if dragState != .idle {
            onDragCancelled?()
        }
        dragState = .idle
        trackedWindow = nil
    }

    // MARK: - Coordinate conversion

    /// Convert NSEvent screen coordinates (origin bottom-left) to CG coordinates (origin top-left)
    private func cgPoint(from nsPoint: NSPoint) -> CGPoint {
        guard let mainScreen = NSScreen.screens.first else { return CGPoint(x: nsPoint.x, y: nsPoint.y) }
        return CGPoint(x: nsPoint.x, y: mainScreen.frame.height - nsPoint.y)
    }

    // MARK: - Accessibility helpers

    private func isOwnWindow(_ window: AXUIElement, ownPID: Int32) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return pid == ownPID
    }

    private func getFocusedWindow() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var appRef: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let app = appRef else { return nil }

        var winRef: AnyObject?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef else { return nil }

        return (win as! AXUIElement)
    }

    private func getWindowAtPosition(_ point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let el = element else { return nil }

        var current: AXUIElement = el
        for _ in 0..<10 {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if (role as? String) == "AXWindow" {
                return current
            }
            var parent: AnyObject?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success else { break }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func getWindowPosition(_ window: AXUIElement) -> CGPoint? {
        var posValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        return point
    }
}

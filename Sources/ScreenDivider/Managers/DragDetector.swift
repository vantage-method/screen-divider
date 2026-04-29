import AppKit
import ApplicationServices

class DragDetector {
    var onDragStarted: ((_ window: AXUIElement) -> Void)?
    var onDragMoved: ((_ cursorPosition: CGPoint) -> Void)?
    var onDragEnded: ((_ cursorPosition: CGPoint, _ window: AXUIElement) -> Void)?
    var onDragCancelled: (() -> Void)?
    var isEnabled: Bool = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dragState: DragState = .idle
    private var trackedWindow: AXUIElement?
    private var lastWindowPosition: CGPoint = .zero
    private var mouseDownPoint: CGPoint = .zero
    private var dragCheckCount: Int = 0

    private enum DragState {
        case idle
        case watching       // mouse is down, checking for window movement each drag event
        case dragging       // confirmed window drag, overlays shown
    }

    // Prevent deallocation while event tap holds a reference
    private var retainedSelf: Unmanaged<DragDetector>?

    func start() {
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                                (1 << CGEventType.leftMouseDragged.rawValue) |
                                (1 << CGEventType.leftMouseUp.rawValue)

        // Use passRetained so the event tap callback always has a valid reference
        retainedSelf = Unmanaged.passRetained(self)
        let refcon = retainedSelf!.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let detector = Unmanaged<DragDetector>.fromOpaque(refcon).takeUnretainedValue()
                detector.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            NSLog("ScreenDivider: FAILED to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("ScreenDivider: Drag detector started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        dragState = .idle
        // Balance the passRetained from start()
        retainedSelf?.release()
        retainedSelf = nil
    }

    private func handleEvent(type: CGEventType, event: CGEvent) {
        guard isEnabled else { return }
        let loc = event.location

        switch type {
        case .leftMouseDown:
            dragState = .idle
            trackedWindow = nil
            dragCheckCount = 0
            mouseDownPoint = loc

            // Try to get a window: first the focused window, then the window at click position
            if let w = getFocusedWindow(), let pos = getWindowPosition(w) {
                trackedWindow = w
                lastWindowPosition = pos
                dragState = .watching
            } else if let w = getWindowAtPosition(loc), let pos = getWindowPosition(w) {
                trackedWindow = w
                lastWindowPosition = pos
                dragState = .watching
            }

        case .leftMouseDragged:
            guard dragState != .idle, let window = trackedWindow else { return }

            if dragState == .watching {
                dragCheckCount += 1
                // Check every 2 events
                if dragCheckCount % 2 != 0 { return }

                // Check if mouse moved enough
                let dx = loc.x - mouseDownPoint.x
                let dy = loc.y - mouseDownPoint.y
                guard sqrt(dx*dx + dy*dy) > 6 else { return }

                // Check if window position changed
                guard let currentPos = getWindowPosition(window) else {
                    dragState = .idle
                    return
                }
                let wdx = currentPos.x - lastWindowPosition.x
                let wdy = currentPos.y - lastWindowPosition.y
                if sqrt(wdx*wdx + wdy*wdy) > 3 {
                    dragState = .dragging
                    NSLog("ScreenDivider: Window drag detected - showing zones")
                    DispatchQueue.main.async { [weak self] in
                        self?.onDragStarted?(window)
                    }
                } else if dragCheckCount > 15 {
                    // Gave it enough chances, not a window drag
                    dragState = .idle
                    trackedWindow = nil
                }
            }

            if dragState == .dragging {
                DispatchQueue.main.async { [weak self] in
                    self?.onDragMoved?(loc)
                }
            }

        case .leftMouseUp:
            if dragState == .dragging, let window = trackedWindow {
                let pt = loc
                DispatchQueue.main.async { [weak self] in
                    self?.onDragEnded?(pt, window)
                }
            } else if dragState != .idle {
                DispatchQueue.main.async { [weak self] in
                    self?.onDragCancelled?()
                }
            }
            dragState = .idle
            trackedWindow = nil

        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }

        default:
            break
        }
    }

    // MARK: - Accessibility helpers

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

        // Walk up to find the window
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

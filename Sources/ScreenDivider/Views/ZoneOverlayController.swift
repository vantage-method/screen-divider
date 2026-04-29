import AppKit

class ZoneOverlayController {
    private var overlayWindows: [(window: NSWindow, view: ZoneOverlayView, screen: NSScreen)] = []
    private var currentConfig: ScreenDividerConfig?

    func showOverlays(for config: ScreenDividerConfig) {
        hideOverlays()
        currentConfig = config

        for screen in NSScreen.screens {
            let screenName = screen.localizedName
            let layout = config.layout(for: screenName) ?? config.screens.first
            guard let layout = layout else { continue }

            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.alphaValue = 0

            let v = ZoneOverlayView(frame: screen.frame)
            v.layout = layout
            v.screen = screen
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                w.animator().alphaValue = 1.0
            }

            overlayWindows.append((window: w, view: v, screen: screen))
        }
    }

    func hideOverlays() {
        let windows = overlayWindows
        overlayWindows.removeAll()
        currentConfig = nil
        for entry in windows {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                entry.window.animator().alphaValue = 0
            }, completionHandler: {
                entry.window.orderOut(nil)
            })
        }
    }

    func updateHover(cursorPosition: CGPoint) {
        guard let config = currentConfig else { return }
        let primaryHeight = NSScreen.screens[0].frame.height
        let nsPoint = NSPoint(x: cursorPosition.x, y: primaryHeight - cursorPosition.y)

        for entry in overlayWindows {
            let screenName = entry.screen.localizedName
            let layout = config.layout(for: screenName) ?? config.screens.first
            guard let layout = layout else { continue }

            if entry.screen.frame.contains(nsPoint) {
                if let hit = CoordinateHelper.zoneAt(point: cursorPosition, layout: layout, screen: entry.screen) {
                    if entry.view.highlightedLabel != hit.label {
                        entry.view.highlightedLabel = hit.label
                        entry.view.needsDisplay = true
                    }
                } else if entry.view.highlightedLabel != nil {
                    entry.view.highlightedLabel = nil
                    entry.view.needsDisplay = true
                }
            } else if entry.view.highlightedLabel != nil {
                entry.view.highlightedLabel = nil
                entry.view.needsDisplay = true
            }
        }
    }

    func snapRectAtPoint(_ point: CGPoint) -> (rect: CGRect, screen: NSScreen)? {
        guard let config = currentConfig else { return nil }
        for entry in overlayWindows {
            let screenName = entry.screen.localizedName
            let layout = config.layout(for: screenName) ?? config.screens.first
            guard let layout = layout else { continue }
            if let hit = CoordinateHelper.zoneAt(point: point, layout: layout, screen: entry.screen) {
                let absRect = CoordinateHelper.absoluteRect(fractional: hit.fractionalRect, on: entry.screen)
                return (rect: absRect, screen: entry.screen)
            }
        }
        return nil
    }
}

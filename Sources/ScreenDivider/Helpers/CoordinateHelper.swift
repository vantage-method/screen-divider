import AppKit

struct CoordinateHelper {
    /// Convert a fractional zone rect (0-1) to absolute screen coordinates for the Accessibility API (top-left origin).
    static func absoluteRect(fractional: CGRect, on screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        let primaryHeight = NSScreen.screens[0].frame.height

        let x = vf.origin.x + fractional.origin.x * vf.width
        let y_bl = vf.origin.y + (1.0 - fractional.origin.y - fractional.height) * vf.height
        let w = fractional.width * vf.width
        let h = fractional.height * vf.height

        // Flip to top-left origin
        let y_tl = primaryHeight - y_bl - h

        return CGRect(x: round(x), y: round(y_tl), width: round(w), height: round(h))
    }

    /// Convert a fractional zone rect (0-1) to view coordinates for overlay drawing.
    /// The view covers screen.frame; zones are within screen.visibleFrame.
    static func viewRect(fractional: CGRect, screen: NSScreen) -> CGRect {
        let sf = screen.frame
        let vf = screen.visibleFrame
        let offsetX = vf.origin.x - sf.origin.x
        let offsetY = vf.origin.y - sf.origin.y

        return CGRect(
            x: offsetX + fractional.origin.x * vf.width,
            y: offsetY + (1.0 - fractional.origin.y - fractional.height) * vf.height,
            width: fractional.width * vf.width,
            height: fractional.height * vf.height
        )
    }

    /// Hit-test: find which zone a point (in global top-left coords) falls in.
    static func zoneAt(point: CGPoint, layout: ScreenLayout, screen: NSScreen) -> (label: String, fractionalRect: CGRect)? {
        let zones = layout.root.flattenZones()
        for z in zones {
            let absRect = absoluteRect(fractional: z.rect, on: screen)
            if absRect.contains(point) {
                return (label: z.label, fractionalRect: z.rect)
            }
        }
        return nil
    }
}

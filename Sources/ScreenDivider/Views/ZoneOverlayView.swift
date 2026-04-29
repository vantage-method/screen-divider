import AppKit

class ZoneOverlayView: NSView {
    var layout: ScreenLayout?
    var screen: NSScreen?
    var highlightedLabel: String?

    override func draw(_ dirtyRect: NSRect) {
        guard let layout = layout, let screen = screen else { return }

        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        let zones = layout.root.flattenZones()
        for z in zones {
            let zoneRect = CoordinateHelper.viewRect(fractional: z.rect, screen: screen).insetBy(dx: 2, dy: 2)
            let isHit = z.label == highlightedLabel

            if isHit {
                NSColor.controlAccentColor.withAlphaComponent(0.30).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.06).setFill()
            }
            let path = NSBezierPath(roundedRect: zoneRect, xRadius: 4, yRadius: 4)
            path.fill()

            if isHit {
                NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 2.0
            } else {
                NSColor.white.withAlphaComponent(0.25).setStroke()
                path.lineWidth = 1.0
            }
            path.stroke()

            let fontSize: CGFloat = isHit ? 14 : 12
            let alpha: CGFloat = isHit ? 0.95 : 0.55
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: isHit ? .medium : .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha)
            ]
            let size = (z.label as NSString).size(withAttributes: attrs)
            let tr = NSRect(x: zoneRect.midX - size.width/2, y: zoneRect.midY - size.height/2,
                           width: size.width + 2, height: size.height)
            (z.label as NSString).draw(in: tr, withAttributes: attrs)
        }
    }
}

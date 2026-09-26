import AppKit

/// Menu bar glyph: a petri dish that collects colonies as your screen does.
enum StatusIcon {
    // Fixed spots so the icon grows predictably: (x, y, radius) in an 18pt box.
    private static let colonies: [(CGFloat, CGFloat, CGFloat)] = [
        (6.5, 11.5, 2.2), (11.5, 6.5, 2.0), (12, 12, 1.5), (6, 6.5, 1.4), (9, 9, 1.8), (9.5, 13.5, 1.1), (13.5, 9.3, 1.0),
    ]

    static func image(progress: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            let dish = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            dish.lineWidth = 1.3
            dish.stroke()
            let shown = Int((Double(colonies.count) * min(1, max(0, progress))).rounded(.up))
            NSColor.black.setFill()
            for (x, y, r) in colonies.prefix(max(1, shown)) {
                let grow = shown == 0 ? 0.35 : 1
                let rr = r * CGFloat(grow)
                NSBezierPath(ovalIn: NSRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

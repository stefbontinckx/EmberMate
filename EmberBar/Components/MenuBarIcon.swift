//
//  MenuBarIcon.swift
//  EmberBar
//
//  A mug outline for the menu bar whose fill follows the liquid level.
//

import AppKit

enum MenuBarIcon {
    // `fill` is 0...1; `check` adds a check mark next to the mug.
    // Drawn as a template image so it adapts to the menu bar.
    static func mug(fill: Double, check: Bool = false) -> NSImage {
        let size = NSSize(width: check ? 30 : 18, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let line: CGFloat = 1.5
            let body = NSRect(x: 2, y: 1.5, width: 10.5, height: 12.5)
            let bodyPath = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)

            // Liquid, clipped to the inside of the body.
            let level = min(max(fill, 0), 1)
            if level > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: body.insetBy(dx: line, dy: line), xRadius: 1.5, yRadius: 1.5).addClip()
                let inner = body.insetBy(dx: line, dy: line)
                NSColor.black.setFill()
                NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * level).fill()
                NSGraphicsContext.restoreGraphicsState()
            }

            NSColor.black.setStroke()
            bodyPath.lineWidth = line
            bodyPath.stroke()

            // Handle.
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: body.maxX, y: 11))
            handle.curve(to: NSPoint(x: body.maxX, y: 4.5),
                         controlPoint1: NSPoint(x: body.maxX + 4.5, y: 11),
                         controlPoint2: NSPoint(x: body.maxX + 4.5, y: 4.5))
            handle.lineWidth = line
            handle.stroke()

            if check {
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: 20, y: 8))
                mark.line(to: NSPoint(x: 23, y: 4.5))
                mark.line(to: NSPoint(x: 28.5, y: 11.5))
                mark.lineWidth = 2
                mark.lineCapStyle = .round
                mark.lineJoinStyle = .round
                mark.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

import AppKit

enum StatusItemIcon {
    enum State {
        case idle
        case recording
        case busy
        case attention
    }

    static func make(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 2.0, y: 7.0))
            fold.curve(
                to: NSPoint(x: 7.4, y: 6.3),
                controlPoint1: NSPoint(x: 3.0, y: 5.0),
                controlPoint2: NSPoint(x: 5.4, y: 4.6)
            )
            fold.line(to: NSPoint(x: 10.6, y: 11.0))
            fold.curve(
                to: NSPoint(x: 13.0, y: 9.8),
                controlPoint1: NSPoint(x: 11.5, y: 12.2),
                controlPoint2: NSPoint(x: 13.0, y: 11.2)
            )
            fold.line(to: NSPoint(x: 13.0, y: 4.0))
            fold.curve(
                to: NSPoint(x: 15.8, y: 3.0),
                controlPoint1: NSPoint(x: 13.0, y: 3.2),
                controlPoint2: NSPoint(x: 14.1, y: 2.4)
            )
            fold.line(to: NSPoint(x: 15.8, y: 10.8))
            fold.curve(
                to: NSPoint(x: 11.6, y: 15.4),
                controlPoint1: NSPoint(x: 15.8, y: 14.0),
                controlPoint2: NSPoint(x: 14.0, y: 15.4)
            )
            fold.curve(
                to: NSPoint(x: 7.2, y: 12.7),
                controlPoint1: NSPoint(x: 9.8, y: 15.4),
                controlPoint2: NSPoint(x: 8.2, y: 14.2)
            )
            fold.line(to: NSPoint(x: 4.0, y: 8.5))
            fold.curve(
                to: NSPoint(x: 2.0, y: 7.0),
                controlPoint1: NSPoint(x: 3.2, y: 7.8),
                controlPoint2: NSPoint(x: 2.5, y: 7.3)
            )
            fold.close()
            fold.fill()

            switch state {
            case .idle:
                break
            case .recording:
                NSBezierPath(ovalIn: NSRect(x: 13.5, y: 2.0, width: 3.2, height: 3.2)).fill()
            case .busy:
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 2.6, width: 1.8, height: 1.8)).fill()
                NSBezierPath(ovalIn: NSRect(x: 15.2, y: 2.6, width: 1.8, height: 1.8)).fill()
            case .attention:
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: 15.2, y: 8.0))
                mark.line(to: NSPoint(x: 15.2, y: 4.7))
                mark.lineWidth = 1.8
                mark.lineCapStyle = .round
                mark.stroke()
                NSBezierPath(ovalIn: NSRect(x: 14.3, y: 1.8, width: 1.8, height: 1.8)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = ProductIdentity.displayName
        return image
    }
}

import AppKit
import VibeKeyLiteCore

enum VibeKeyStatusIcon {
    static func image(for profile: ProfileID) -> NSImage? {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            drawRemote(profile: profile)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "VibeKey Lite：\(profile.displayName)"
        return image
    }

    private static func drawRemote(profile: ProfileID) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let body = NSBezierPath(
            roundedRect: NSRect(x: 3.25, y: 0.75, width: 8.5, height: 16.5),
            xRadius: 2.1,
            yRadius: 2.1
        )
        body.lineWidth = 1.15
        body.stroke()

        let speaker = NSBezierPath()
        speaker.lineWidth = 0.9
        speaker.lineCapStyle = .round
        speaker.move(to: NSPoint(x: 5.4, y: 14.8))
        speaker.line(to: NSPoint(x: 9.6, y: 14.8))
        speaker.stroke()

        let knob = NSBezierPath(ovalIn: NSRect(x: 4.6, y: 8.0, width: 5.8, height: 5.8))
        knob.lineWidth = 1.05
        knob.stroke()

        let knobMark = NSBezierPath()
        knobMark.lineWidth = 0.85
        knobMark.lineCapStyle = .round
        knobMark.move(to: NSPoint(x: 7.5, y: 12.75))
        knobMark.line(to: NSPoint(x: 7.5, y: 11.8))
        knobMark.stroke()

        for y in [6.4, 4.25, 2.15] as [CGFloat] {
            let button = NSBezierPath(ovalIn: NSRect(x: 6.55, y: y, width: 1.9, height: 1.15))
            button.fill()
        }

        switch profile {
        case .a:
            drawSparkle()
        case .b:
            drawSliders()
        }
    }

    private static func drawSparkle() {
        let sparkle = NSBezierPath()
        sparkle.lineWidth = 1.05
        sparkle.lineCapStyle = .round
        sparkle.move(to: NSPoint(x: 14.5, y: 11.4))
        sparkle.line(to: NSPoint(x: 14.5, y: 16.4))
        sparkle.move(to: NSPoint(x: 12.1, y: 13.9))
        sparkle.line(to: NSPoint(x: 16.9, y: 13.9))
        sparkle.stroke()

        let accent = NSBezierPath()
        accent.lineWidth = 0.85
        accent.lineCapStyle = .round
        accent.move(to: NSPoint(x: 12.5, y: 16.0))
        accent.line(to: NSPoint(x: 13.2, y: 16.7))
        accent.stroke()
    }

    private static func drawSliders() {
        let sliders = NSBezierPath()
        sliders.lineWidth = 0.95
        sliders.lineCapStyle = .round
        sliders.move(to: NSPoint(x: 12.5, y: 15.1))
        sliders.line(to: NSPoint(x: 16.8, y: 15.1))
        sliders.move(to: NSPoint(x: 12.5, y: 12.2))
        sliders.line(to: NSPoint(x: 16.8, y: 12.2))
        sliders.stroke()

        NSBezierPath(ovalIn: NSRect(x: 13.2, y: 14.25, width: 1.7, height: 1.7)).fill()
        NSBezierPath(ovalIn: NSRect(x: 15.0, y: 11.35, width: 1.7, height: 1.7)).fill()
    }
}

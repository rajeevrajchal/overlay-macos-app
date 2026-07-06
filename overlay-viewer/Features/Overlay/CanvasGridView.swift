import Cocoa

/// A tiled dot grid drawn at a fixed, low alpha — the same role as
/// react-flow's `<Background variant="dots" />` or Figma's canvas dots, drawn
/// natively instead of as SVG/CSS.
///
/// It sits *behind* the reference image and is the transparency reference the
/// eye calibrates against: as the image fades toward invisible via the opacity
/// slider, this constant layer keeps the window from reading as "broken/gone."
///
/// Deliberately owns exactly one concern — draw dots at a fixed alpha. Its
/// alpha is a constant here and is never bound to the overlay's opacity value;
/// if it ever needs its own fade (e.g. auto-dim on idle) that belongs to a
/// separate property, not this one.
final class CanvasGridView: NSView {

    /// Distance between dot centers.
    var spacing: CGFloat = 16
    /// Dot diameter in points.
    var dotDiameter: CGFloat = 1.5
    /// Fixed, low-contrast fill — recedes when an image is present, only
    /// asserts itself when the image is faint or absent. Never tied to opacity.
    var dotColor: NSColor = NSColor.labelColor.withAlphaComponent(0.08)
    /// A faint neutral wash behind the dots so the window reads as a real panel
    /// with a visible border even when the image is faded to nothing — rather
    /// than dissolving into the desktop. Kept low so the overlay stays usably
    /// see-through. Fixed alpha, never tied to opacity.
    var panelColor: NSColor = NSColor(white: 0.5, alpha: 0.14)

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Redraw the dots in step with each live-resize frame instead of letting
        // Core Animation stretch stale layer contents (which shimmers/flickers
        // the grid as the window is dragged).
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }

    // Redraw the whole grid when resized so dots retile cleanly.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    // Pure visual layer: never intercept clicks, drags, or window moves.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Faint neutral wash so the window's bounds and border stay visible at
        // any image opacity, while remaining translucent enough to compare
        // against what's underneath.
        panelColor.set()
        dirtyRect.fill()

        guard spacing > 0 else { return }
        dotColor.setFill()

        let inset = (spacing - dotDiameter) / 2
        var x = inset
        while x < bounds.width {
            var y = inset
            while y < bounds.height {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotDiameter, height: dotDiameter)).fill()
                y += spacing
            }
            x += spacing
        }
    }
}

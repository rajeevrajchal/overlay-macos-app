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
        // The whole grid — panel wash plus dots — is baked into a single
        // `spacing × spacing` tile and set as the backing layer's *pattern*
        // background, so Core Animation tiles it on the GPU as the window
        // resizes: no per-frame `draw(_:)`, and nothing for CA to stretch. This
        // is the same GPU-scaling strategy `ImageCanvasView` uses for the image,
        // and it's what keeps live resize — especially shrinking, and the custom
        // `ResizeHandleView` path that never enters AppKit's live-resize loop —
        // free of the stale-bitmap shimmer a redraw-per-frame grid produced.
        layerContentsRedrawPolicy = .never
        applyPattern()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Pure visual layer: never intercept clicks, drags, or window moves.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPattern()   // pick up the window's backing scale for a crisp tile
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyPattern()   // regenerate the tile when the display scale changes
    }

    /// Paint one grid tile and hand it to the layer as a repeating pattern. The
    /// tile carries the faint panel wash so the window's bounds/border stay
    /// visible at any image opacity, plus a single dot; tiling reproduces the
    /// full dot grid for free, extending or contracting with the layer on resize.
    private func applyPattern() {
        guard spacing > 0, let tile = makeTile() else { return }
        layer?.backgroundColor = NSColor(patternImage: tile).cgColor
    }

    private func makeTile() -> NSImage? {
        let size = NSSize(width: spacing, height: spacing)
        guard size.width > 0, size.height > 0 else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        panelColor.set()
        NSRect(origin: .zero, size: size).fill()
        dotColor.setFill()
        let inset = (spacing - dotDiameter) / 2
        NSBezierPath(ovalIn: NSRect(x: inset, y: inset, width: dotDiameter, height: dotDiameter)).fill()
        image.unlockFocus()
        return image
    }
}

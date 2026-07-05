import Cocoa

/// Pure rendering surface. Single Responsibility: draw an image, scaled to fill
/// (or free-form stretch), at a given content opacity. It has zero knowledge of window levels, dragging,
/// or menus — that separation means you could drop this view into a totally
/// different host (a sheet, a popover, a test harness) and it would behave identically.
final class ImageCanvasView: NSView {

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    /// Content-only opacity. This fades the IMAGE PIXELS, independent of
    /// the window's own alphaValue. See OverlayWindowController for why
    /// these two are kept deliberately separate.
    var contentOpacity: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    /// When true, the image keeps its original proportions and is scaled to
    /// *fit* the bounds (aspect-fit): the whole image is always visible, scaled
    /// uniformly — never cropped, never distorted. The host locks the window's
    /// resize to the image's aspect ratio, so a drag scales the image
    /// proportionally with no letterboxing (the automatic "Shift-drag" feel).
    /// When false, it is stretched to fill the bounds exactly, distorting
    /// proportions so dragging any edge scales the image along that axis — the
    /// free-form "match an irregular reference" mode. The window's resize
    /// constraint is kept in step with this by the host (see
    /// OverlayWindowController).
    var aspectLocked: Bool = true {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }

        // Clear to fully transparent first — critical, since the window
        // background is .clear and we don't want any default fill leaking through.
        NSColor.clear.set()
        dirtyRect.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let viewSize = bounds.size
        let drawRect: NSRect
        if aspectLocked {
            // Aspect-fit (proportional scale): scale by the SMALLER ratio so the
            // WHOLE image is always visible, uniformly scaled — never cropped,
            // never distorted. Paired with the window's aspect-ratio-locked
            // resize (ResizeHandleView.aspectRatio), a drag scales the image
            // proportionally with zero letterboxing — the automatic "Shift-drag"
            // feel. If the window is ever forced to a mismatched ratio (numeric
            // size popover), the image still shows in full, centered.
            let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
            let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = NSPoint(
                x: (viewSize.width - drawSize.width) / 2,
                y: (viewSize.height - drawSize.height) / 2
            )
            drawRect = NSRect(origin: origin, size: drawSize)
        } else {
            // Free-form: stretch to fill the bounds exactly. `image.draw(in:)`
            // scales from NSImage's cached representation, so this is a cheap
            // re-render per resize tick, not a re-decode.
            drawRect = NSRect(origin: .zero, size: viewSize)
        }

        // Defensive clip to our bounds: both modes draw within bounds today, but
        // `NSView.clipsToBounds` defaults to `false` on the macOS 14+ SDK, so
        // guard against any sub-pixel rounding spilling a stray edge. This is the
        // AppKit equivalent of SwiftUI's `.clipped()`.
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        image.draw(in: drawRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: contentOpacity)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

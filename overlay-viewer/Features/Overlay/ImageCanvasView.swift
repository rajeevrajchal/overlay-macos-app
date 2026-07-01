import Cocoa

/// Pure rendering surface. Single Responsibility: draw an image, scaled to fit,
/// at a given content opacity. It has zero knowledge of window levels, dragging,
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

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }

        // Clear to fully transparent first — critical, since the window
        // background is .clear and we don't want any default fill leaking through.
        NSColor.clear.set()
        dirtyRect.fill()

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        // Aspect-fit within the view bounds.
        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = NSPoint(
            x: (viewSize.width - drawSize.width) / 2,
            y: (viewSize.height - drawSize.height) / 2
        )
        let drawRect = NSRect(origin: origin, size: drawSize)

        image.draw(in: drawRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: contentOpacity)
    }
}

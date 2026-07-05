import Cocoa

/// Pure rendering surface. Single Responsibility: show one image, scaled to fit
/// (or free-form stretch), at a given content opacity. It has zero knowledge of
/// window levels, dragging, or menus — that separation means you could drop this
/// view into a totally different host (a sheet, a popover, a test harness) and it
/// would behave identically.
///
/// The image lives in a dedicated CALayer's `contents`, so Core Animation scales
/// it on the GPU during live window resize — no per-frame `draw(_:)`, no
/// clear-to-transparent flash between frames. That is what keeps resizing smooth
/// and flicker-free (the old `image.draw(in:)`-per-frame path flickered because
/// every resize tick cleared the view and re-rasterized the whole image).
final class ImageCanvasView: NSView {

    var image: NSImage? {
        didSet { updateContents() }
    }

    /// Content-only opacity. This fades the IMAGE PIXELS (the image layer),
    /// independent of the window's own alphaValue and of the grid behind it.
    /// See OverlayWindowController for why these are kept deliberately separate.
    var contentOpacity: CGFloat = 1.0 {
        didSet { applyOpacity() }
    }

    /// When true, the image keeps its original proportions and is scaled to
    /// *fit* the bounds (`.resizeAspect`): the whole image is always visible,
    /// scaled uniformly — never cropped, never distorted. The host locks the
    /// window's resize to the image's aspect ratio, so a drag scales the image
    /// proportionally with no letterboxing (the automatic "Shift-drag" feel).
    /// When false, it is stretched to fill the bounds exactly (`.resize`),
    /// distorting proportions — the free-form "match an irregular reference"
    /// mode. The host keeps the window's resize constraint in step (see
    /// OverlayWindowController).
    var aspectLocked: Bool = true {
        didSet { applyGravity() }
    }

    /// Holds the image texture; CA scales it to our bounds every frame for free.
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Contain any overflow (belt-and-suspenders for the stretch case, and a
        // guard against sub-pixel spill on the macOS 14+ SDK where clipsToBounds
        // defaults to false).
        layer?.masksToBounds = true
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        applyGravity()
        applyOpacity()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // Keep the image layer exactly matching our bounds. Disable implicit
        // actions so the bounds change tracks the live resize instantly instead
        // of animating a frame behind the cursor (which reads as lag/flicker).
        withoutAnimation {
            imageLayer.frame = bounds
            imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Follow the image across displays with different scale factors so it
        // stays crisp (Retina ↔ non-Retina).
        withoutAnimation {
            imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    private func updateContents() {
        withoutAnimation {
            imageLayer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        }
    }

    private func applyGravity() {
        withoutAnimation {
            imageLayer.contentsGravity = aspectLocked ? .resizeAspect : .resize
        }
    }

    private func applyOpacity() {
        withoutAnimation {
            imageLayer.opacity = Float(contentOpacity)
        }
    }

    /// Run layer mutations with implicit animations off. During a live resize,
    /// the default 0.25s implicit animation on `frame`/`contents` would lag the
    /// image behind the window edge — the visible "flicker/stutter".
    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

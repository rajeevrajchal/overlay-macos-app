import Cocoa

/// Transparent edge/corner drag-to-resize affordance for borderless windows,
/// which get no resize cursors or hit-areas from AppKit for free. Add as the
/// LAST subview of a window's content view (autoresizingMask = [.width, .height])
/// so it sits on top; it hit-tests to nil everywhere except a thin strip near
/// each edge, so clicks elsewhere fall through to the views underneath.
final class ResizeHandleView: NSView {

    private let edgeThreshold: CGFloat = 8
    private let minSize: NSSize
    private var resizeEdge: Edge = .none
    private var dragStartScreen: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    /// The window's `hasShadow` before a drag, restored on mouse-up.
    private var savedHasShadow = true

    /// When set (width / height of the content being displayed), interactive
    /// resize is constrained to this ratio so the content always fills the
    /// window with no letterboxing — instead of free-form resize leaving
    /// empty margin wherever the dragged rect doesn't match the content's
    /// proportions. `chromeHeight` is subtracted from the window height
    /// before applying the ratio, for fixed-height UI (e.g. a toolbar) that
    /// isn't part of the aspect-locked content itself.
    var aspectRatio: CGFloat?
    var chromeHeight: CGFloat = 0

    enum Edge {
        case none
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

    init(minSize: NSSize, frame: NSRect = .zero) {
        self.minSize = minSize
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tracking Area

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard detectEdge(for: point) != .none else { return nil }
        return self
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        setCursor(for: detectEdge(for: local))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        resizeEdge = detectEdge(for: local)
        guard resizeEdge != .none, let win = window else { return }
        dragStartScreen = win.convertPoint(toScreen: event.locationInWindow)
        dragStartFrame = win.frame

        // The window is transparent + shadowed, so AppKit recomputes the drop
        // shadow from the content's alpha shape on every resize step — a per-tick
        // cost that flickers the edges. Drop it for the duration of the drag and
        // restore it (recomputed once) on mouse-up.
        savedHasShadow = win.hasShadow
        win.hasShadow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizeEdge != .none, let win = window else { return }
        let current = win.convertPoint(toScreen: event.locationInWindow)
        let dx = current.x - dragStartScreen.x
        let dy = current.y - dragStartScreen.y

        var (width, height) = rawProposedSize(dx: dx, dy: dy)
        if let aspectRatio {
            (width, height) = applyAspectRatio(aspectRatio, toWidth: width, height: height, dx: dx, dy: dy)
        }
        let origin = anchoredOrigin(forWidth: width, height: height)

        // Apply the frame change inside a CATransaction with implicit actions
        // off so the window's layer-backed subviews (image layer, grid) resize in
        // lock-step with the window frame in a single commit — rather than the
        // frame jumping this tick and the layer content easing to catch up next
        // tick, which reads as flicker when shrinking.
        //
        // `display: false`: every piece of content is now a GPU-composited layer
        // (image layer, the grid's pattern background, the toolbar's material),
        // so there's nothing to redraw on the CPU each tick. Letting the frame +
        // layers settle in the CA commit — instead of forcing a synchronous
        // per-event redraw pass — is what makes the shrink fully smooth.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        win.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        resizeEdge = .none
        NSCursor.arrow.set()
        if let win = window {
            win.hasShadow = savedHasShadow
            win.invalidateShadow()   // recompute the shadow once, for the final shape
        }
    }

    // MARK: - Resize math

    /// Width/height driven purely by cursor movement along the axis (or axes)
    /// implied by the dragged edge, clamped to minSize — identical to the
    /// original free-form per-edge behavior, before any aspect correction.
    private func rawProposedSize(dx: CGFloat, dy: CGFloat) -> (width: CGFloat, height: CGFloat) {
        var width = dragStartFrame.width
        var height = dragStartFrame.height

        switch resizeEdge {
        case .left, .topLeft, .bottomLeft:
            width = dragStartFrame.width - dx
        case .right, .topRight, .bottomRight:
            width = dragStartFrame.width + dx
        case .top, .bottom, .none:
            break
        }

        switch resizeEdge {
        case .top, .topLeft, .topRight:
            height = dragStartFrame.height + dy
        case .bottom, .bottomLeft, .bottomRight:
            height = dragStartFrame.height - dy
        case .left, .right, .none:
            break
        }

        return (max(minSize.width, width), max(minSize.height, height))
    }

    /// Re-derives whichever dimension isn't directly driven by the cursor so
    /// width:height stays locked to `ratio` (after excluding chromeHeight from
    /// the height side of that ratio). The driven axis is whatever the edge
    /// implies (left/right -> width, top/bottom -> height); for corners it's
    /// whichever axis the user is moving the mouse more along.
    private func applyAspectRatio(
        _ ratio: CGFloat, toWidth width: CGFloat, height: CGFloat, dx: CGFloat, dy: CGFloat
    ) -> (width: CGFloat, height: CGFloat) {
        let widthIsDriven: Bool
        switch resizeEdge {
        case .left, .right: widthIsDriven = true
        case .top, .bottom: widthIsDriven = false
        default: widthIsDriven = abs(dx) >= abs(dy)
        }

        var width = width
        var height = height

        if widthIsDriven {
            height = width / ratio + chromeHeight
            if height < minSize.height {
                height = minSize.height
                width = max(minSize.width, (height - chromeHeight) * ratio)
            }
        } else {
            width = (height - chromeHeight) * ratio
            if width < minSize.width {
                width = minSize.width
                height = max(minSize.height, width / ratio + chromeHeight)
            }
        }

        return (max(minSize.width, width), max(minSize.height, height))
    }

    /// The edge/corner being dragged tracks the cursor; whichever edge(s) are
    /// diagonally opposite stay fixed in place, e.g. dragging the bottom-right
    /// corner pins the top-left corner regardless of how width/height were
    /// derived above.
    private func anchoredOrigin(forWidth width: CGFloat, height: CGFloat) -> NSPoint {
        let x: CGFloat
        let y: CGFloat

        switch resizeEdge {
        case .left, .topLeft, .bottomLeft:
            x = dragStartFrame.maxX - width
        case .right, .topRight, .bottomRight:
            x = dragStartFrame.minX
        case .top, .bottom, .none:
            x = dragStartFrame.midX - width / 2
        }

        switch resizeEdge {
        case .top, .topLeft, .topRight:
            y = dragStartFrame.minY
        case .bottom, .bottomLeft, .bottomRight:
            y = dragStartFrame.maxY - height
        case .left, .right, .none:
            y = dragStartFrame.midY - height / 2
        }

        return NSPoint(x: x, y: y)
    }

    // MARK: - Helpers

    private func detectEdge(for point: NSPoint) -> Edge {
        let t = edgeThreshold
        let b = bounds
        let nearLeft   = point.x < t
        let nearRight  = point.x > b.width - t
        let nearTop    = point.y > b.height - t
        let nearBottom = point.y < t

        if nearTop    && nearLeft  { return .topLeft }
        if nearTop    && nearRight { return .topRight }
        if nearBottom && nearLeft  { return .bottomLeft }
        if nearBottom && nearRight { return .bottomRight }
        if nearLeft   { return .left }
        if nearRight  { return .right }
        if nearTop    { return .top }
        if nearBottom { return .bottom }
        return .none
    }

    private func setCursor(for edge: Edge) {
        switch edge {
        case .left, .right:           NSCursor.resizeLeftRight.set()
        case .top, .bottom:           NSCursor.resizeUpDown.set()
        case .topLeft, .bottomRight:  NSCursor.crosshair.set()
        case .topRight, .bottomLeft:  NSCursor.crosshair.set()
        case .none:                   NSCursor.arrow.set()
        }
    }
}

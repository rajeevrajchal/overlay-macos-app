import Cocoa
import UniformTypeIdentifiers


// MARK: - WelcomeWindow

/// A borderless, frosted-glass floating window used as the app's launch/welcome screen.
/// Resizable from all 8 directions via `ResizeHandleView`.
final class WelcomeWindow: NSWindow {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 500),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 200, height: 300)
        collectionBehavior = [.canJoinAllSpaces, .transient]
    }
}


// MARK: - WelcomeWindowController

/// Controls the Welcome Box lifecycle.
/// Shows a frosted-glass prompt asking the user to click to open an image.
final class WelcomeWindowController: NSWindowController {

    /// Called when the user successfully picks an image.
    /// `OverlayWindowController` sets this before showing the window.
    var onImagePicked: ((URL) -> Void)?

    /// Guards against opening two file pickers simultaneously.
    private var isPresenting = false

    convenience init() {
        let win = WelcomeWindow()
        self.init(window: win)
        buildUI(in: win)
        win.center()
    }

    // MARK: - UI Construction

    private func buildUI(in win: NSWindow) {
        // 1. Root frosted-glass container
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.autoresizingMask = [.width, .height]
        win.contentView = effect

        // 2. Ribbon (top strip, 40 pt tall)
        let ribbonHeight: CGFloat = 40
        let ribbon = RibbonView(frame: NSRect(x: 0, y: 460, width: 300, height: ribbonHeight))
        ribbon.autoresizingMask = [.width, .minYMargin]  // pins to top
        // Close button inside ribbon
        let closeBtn = NSButton(frame: NSRect(x: 8, y: 8, width: 24, height: 24))
        closeBtn.bezelStyle = .circular
        closeBtn.title = "\u{00D7}"
        closeBtn.font = .systemFont(ofSize: 14, weight: .bold)
        closeBtn.contentTintColor = .white
        closeBtn.target = self
        closeBtn.action = #selector(closeWelcome)
        closeBtn.autoresizingMask = []
        ribbon.addSubview(closeBtn)
        effect.addSubview(ribbon)

        // 3. Body (below ribbon)
        let body = ClickableBodyView(frame: NSRect(x: 0, y: 0, width: 300, height: 460))
        body.autoresizingMask = [.width, .height]
        body.onClicked = { [weak self] in self?.presentOpenPanel() }
        // SF Symbol icon
        let iconView = NSImageView(frame: NSRect(x: 75, y: 230, width: 150, height: 150))
        iconView.image = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                  accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        iconView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        body.addSubview(iconView)
        // Label
        let label = NSTextField(labelWithString: "Click to open an image")
        label.frame = NSRect(x: 20, y: 200, width: 260, height: 24)
        label.alignment = .center
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        body.addSubview(label)
        effect.addSubview(body)

        // 4. Resize handle overlay (must be added LAST so it's on top)
        let resizer = ResizeHandleView(frame: effect.bounds)
        resizer.autoresizingMask = [.width, .height]
        effect.addSubview(resizer)
    }

    // MARK: - Actions

    @objc private func closeWelcome() {
        window?.orderOut(nil)
    }

    func presentOpenPanel() {
        guard !isPresenting else { return }
        isPresenting = true

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            self?.isPresenting = false
            guard response == .OK, let url = panel.url else { return }
            self?.window?.orderOut(nil)
            self?.onImagePicked?(url)
        }
    }
}


// MARK: - RibbonView

/// Slightly darker tinted strip at top — provides visual separation from body.
private final class RibbonView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }
}


// MARK: - ClickableBodyView

/// Captures clicks in the center body area and fires the open panel.
private final class ClickableBodyView: NSView {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    /// Change cursor to indicate clickability.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}


// MARK: - ResizeHandleView

/// Transparent overlay that intercepts mouseDown near edges/corners and
/// resizes the window in the appropriate direction.
private final class ResizeHandleView: NSView {

    private let edgeThreshold: CGFloat = 8
    private var resizeEdge: Edge = .none
    private var dragStartScreen: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero

    enum Edge {
        case none
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
    }

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
        // Only claim the event if the cursor is near an edge
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
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizeEdge != .none, let win = window else { return }
        let current = win.convertPoint(toScreen: event.locationInWindow)
        let dx = current.x - dragStartScreen.x
        let dy = current.y - dragStartScreen.y
        var frame = dragStartFrame
        let minW: CGFloat = 200
        let minH: CGFloat = 300

        switch resizeEdge {
        case .right:
            frame.size.width = max(minW, dragStartFrame.width + dx)
        case .left:
            let newW = max(minW, dragStartFrame.width - dx)
            frame.origin.x = dragStartFrame.maxX - newW
            frame.size.width = newW
        case .top:
            frame.size.height = max(minH, dragStartFrame.height + dy)
        case .bottom:
            let newH = max(minH, dragStartFrame.height - dy)
            frame.origin.y = dragStartFrame.maxY - newH
            frame.size.height = newH
        case .topRight:
            frame.size.width = max(minW, dragStartFrame.width + dx)
            frame.size.height = max(minH, dragStartFrame.height + dy)
        case .topLeft:
            let newW = max(minW, dragStartFrame.width - dx)
            frame.origin.x = dragStartFrame.maxX - newW
            frame.size.width = newW
            frame.size.height = max(minH, dragStartFrame.height + dy)
        case .bottomRight:
            frame.size.width = max(minW, dragStartFrame.width + dx)
            let newH = max(minH, dragStartFrame.height - dy)
            frame.origin.y = dragStartFrame.maxY - newH
            frame.size.height = newH
        case .bottomLeft:
            let newW = max(minW, dragStartFrame.width - dx)
            frame.origin.x = dragStartFrame.maxX - newW
            frame.size.width = newW
            let newH = max(minH, dragStartFrame.height - dy)
            frame.origin.y = dragStartFrame.maxY - newH
            frame.size.height = newH
        case .none:
            break
        }
        win.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        resizeEdge = .none
        NSCursor.arrow.set()
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

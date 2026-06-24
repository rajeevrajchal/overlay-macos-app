import Cocoa
import UniformTypeIdentifiers


/// Owns the OverlayWindow's lifecycle and exposes the user-facing controls:
/// open image, two independent opacity modes, click-through toggle, visibility toggle.
///
/// This is the ONLY class that knows about both OverlayWindow and ImageCanvasView —
/// that's intentional. Everything else in the app talks to this controller, never
/// directly to the window or the view. One seam, easy to test, easy to extend.
final class OverlayWindowController: NSWindowController {

    private let canvasView = ImageCanvasView()
    private var toolbarWindow: ToolbarWindow?

    // MARK: - Init

    convenience init() {
        let window = OverlayWindow()
        self.init(window: window)
        window.contentView = canvasView
        window.delegate = self
    }

    // MARK: - Public API

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.load(imageURL: url)
        }
    }

    func showOpenPanelIfNeeded() {
        if canvasView.image == nil {
            presentOpenPanel()
        }
    }

    func clearAndReopen() {
        canvasView.image = nil
        window?.orderOut(nil)   // hide overlay while picker is open
        presentOpenPanel()      // immediately show file picker
    }

    func toggleVisibility() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
            toolbarWindow?.orderOut(nil)
        } else {
            window.orderFrontRegardless()
            toolbarWindow?.orderFrontRegardless()
        }
    }

    // MARK: - Image loading

    private func load(imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }
        canvasView.image = image

        // Size the window to the image's native aspect ratio, capped to something reasonable.
        let maxDimension: CGFloat = 800
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let windowSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        window?.setContentSize(windowSize)
        window?.center()
        window?.orderFrontRegardless() // shows window WITHOUT activating the app (key for "always on top, never stealing focus")

        showToolbar()
    }

    // MARK: - Opacity controls (the two-knob design)

    /// WINDOW alpha — fades the entire window, including any chrome.
    /// Use for "ghost the whole tool out of the way" behavior.
    func setWindowOpacity(_ value: CGFloat) {
        window?.alphaValue = value
    }

    /// CONTENT alpha — fades only the image pixels. The toolbar (a separate
    /// child window) stays fully opaque so you can keep adjusting controls
    /// while seeing through the reference image underneath.
    func setContentOpacity(_ value: CGFloat) {
        canvasView.contentOpacity = value
    }

    /// Click-through: lets mouse events pass to whatever app is behind the
    /// overlay. Essential for a "trace over" workflow — you don't want the
    /// reference image stealing clicks meant for the app underneath.
    func setClickThrough(_ enabled: Bool) {
        window?.ignoresMouseEvents = enabled
    }

    // MARK: - Toolbar (separate small floating window with the sliders)

    private func showToolbar() {
        guard toolbarWindow == nil, let mainWindow = window else { return }
        let toolbar = ToolbarWindow(controller: self)
        toolbar.order(.above, relativeTo: mainWindow.windowNumber)
        self.toolbarWindow = toolbar
        repositionToolbar()
    }

    private func repositionToolbar() {
        guard let window, let toolbarWindow else { return }
        let frame = window.frame
        let toolbarFrame = NSRect(
            x: frame.minX,
            y: frame.minY - toolbarWindow.frame.height - 8,
            width: toolbarWindow.frame.width,
            height: toolbarWindow.frame.height
        )
        toolbarWindow.setFrame(toolbarFrame, display: true)
    }
}

extension OverlayWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        repositionToolbar()
    }
    func windowDidResize(_ notification: Notification) {
        repositionToolbar()
    }
}

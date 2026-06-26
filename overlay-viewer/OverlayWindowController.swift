import Cocoa
import UniformTypeIdentifiers


// MARK: - OverlayContainerView

/// Root content view of OverlayWindow.
/// Owns the black border (via CALayer) and hosts the toolbar ribbon + canvas.
final class OverlayContainerView: NSView {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.borderColor = NSColor.black.cgColor
        layer?.borderWidth = 1.5
        // backgroundColor stays nil (inherits window's clear background)
    }
}


// MARK: - ToolbarRibbonView

/// 36pt tall strip at the top of OverlayWindow.
/// Background: semi-transparent dark; always fully drawn (opacity independent of image opacity).
/// Draggable: does NOT intercept mouse events in non-control areas,
/// allowing isMovableByWindowBackground to handle window dragging.
final class ToolbarRibbonView: NSView {

    static let height: CGFloat = 36

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent dark ribbon background
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
    }
}


// MARK: - OverlayWindowController

/// Owns the OverlayWindow's lifecycle and exposes the user-facing controls:
/// open image, window opacity, visibility toggle.
///
/// This is the ONLY class that knows about both OverlayWindow and ImageCanvasView —
/// that's intentional. Everything else in the app talks to this controller, never
/// directly to the window or the view. One seam, easy to test, easy to extend.
final class OverlayWindowController: NSWindowController {

    private let canvasView = ImageCanvasView()
    private var toolbarRibbon: ToolbarRibbonView?
    // toolbarWindow is DELETED — toolbar is now embedded in the overlay window
    private var welcomeController: WelcomeWindowController?

    // MARK: - Init

    convenience init() {
        let window = OverlayWindow()
        self.init(window: window)

        // Container: full-size root view that holds the border
        let container = OverlayContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400)
        )
        container.autoresizingMask = [.width, .height]

        // Ribbon: 36pt top strip
        let ribbonHeight = ToolbarRibbonView.height
        let ribbon = buildToolbarRibbon()
        ribbon.frame = NSRect(
            x: 0,
            y: container.bounds.height - ribbonHeight,
            width: container.bounds.width,
            height: ribbonHeight
        )
        ribbon.autoresizingMask = [.width, .minYMargin]

        // Canvas: fills below ribbon
        canvasView.frame = NSRect(
            x: 0,
            y: 0,
            width: container.bounds.width,
            height: container.bounds.height - ribbonHeight
        )
        canvasView.autoresizingMask = [.width, .height]

        container.addSubview(canvasView)
        container.addSubview(ribbon)
        window.contentView = container
        window.delegate = self
        window.minSize = NSSize(width: 400, height: ribbonHeight + 60)

        self.toolbarRibbon = ribbon
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

    // NOTE: This method is no longer called externally.
    // Use showWelcomeWindow() for first-launch flow.
    // Kept for potential internal testing/fallback use.
    func showOpenPanelIfNeeded() {
        if canvasView.image == nil {
            presentOpenPanel()
        }
    }

    /// Shows the Welcome Box centered on screen.
    /// Called on launch (if no image loaded) and from "Open Image…" menu when no image is loaded.
    func showWelcomeWindow() {
        if welcomeController == nil {
            let wc = WelcomeWindowController()
            wc.onImagePicked = { [weak self] url in
                self?.load(imageURL: url)
            }
            welcomeController = wc
        }
        welcomeController?.window?.center()
        welcomeController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// If an image is already loaded, open the raw file picker (mid-session "replace" feel).
    /// If no image is loaded, show the Welcome Box (onboarding feel).
    func presentOpenPanelOrWelcome() {
        if canvasView.image == nil {
            showWelcomeWindow()
        } else {
            presentOpenPanel()
        }
    }

    func clearAndReopen() {
        canvasView.image = nil
        window?.orderOut(nil)
        // NOTE: toolbar ribbon remains in window — it will be visible when window returns.
        // This is intentional: the ribbon is always present.
        presentOpenPanel()
    }

    func toggleVisibility() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
            // Toolbar is embedded — hides with the window automatically
        } else {
            window.orderFrontRegardless()
            // Toolbar is embedded — shows with the window automatically
        }
    }

    // MARK: - Image loading

    private func load(imageURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else { return }
        welcomeController?.window?.orderOut(nil)  // dismiss welcome box on successful load
        canvasView.image = image

        // Size the window to the image's native aspect ratio, capped to something reasonable.
        let maxDimension: CGFloat = 800
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        // Account for ribbon height in window size — canvas should be image-sized, not window-sized
        let ribbonHeight = ToolbarRibbonView.height
        let windowSize = NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale + ribbonHeight   // +36pt for ribbon
        )

        window?.setContentSize(windowSize)
        window?.center()
        window?.orderFrontRegardless()
        // showToolbar() REMOVED — toolbar ribbon always present since init
    }

    // MARK: - Build Toolbar Ribbon

    private func buildToolbarRibbon() -> ToolbarRibbonView {
        let ribbon = ToolbarRibbonView(frame: .zero)  // frame set by caller

        // Close button
        let closeBtn = NSButton(frame: NSRect(x: 8, y: 7, width: 28, height: 22))
        closeBtn.title = "×"
        closeBtn.bezelStyle = .rounded
        closeBtn.font = .systemFont(ofSize: 14, weight: .bold)
        closeBtn.contentTintColor = .white
        closeBtn.target = self
        closeBtn.action = #selector(closeOverlay)
        closeBtn.autoresizingMask = []

        // Change Image button
        let changeBtn = NSButton(frame: NSRect(x: 44, y: 7, width: 76, height: 22))
        changeBtn.title = "Change…"
        changeBtn.bezelStyle = .rounded
        changeBtn.font = .systemFont(ofSize: 11)
        changeBtn.target = self
        changeBtn.action = #selector(changeImageAction)
        changeBtn.autoresizingMask = []

        // Remove Image button
        let removeBtn = NSButton(frame: NSRect(x: 128, y: 7, width: 76, height: 22))
        removeBtn.title = "Remove"
        removeBtn.bezelStyle = .rounded
        removeBtn.font = .systemFont(ofSize: 11)
        removeBtn.target = self
        removeBtn.action = #selector(removeImageAction)
        removeBtn.autoresizingMask = []

        // Opacity label
        let opacityLabel = NSTextField(labelWithString: "Opacity")
        opacityLabel.frame = NSRect(x: 212, y: 10, width: 52, height: 16)
        opacityLabel.textColor = .white
        opacityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        opacityLabel.autoresizingMask = []

        // Opacity slider (fixed 120pt width)
        let opacitySlider = NSSlider(
            value: 1.0, minValue: 0.05, maxValue: 1.0,
            target: self, action: #selector(windowOpacityChanged(_:))
        )
        opacitySlider.frame = NSRect(x: 268, y: 8, width: 120, height: 20)
        opacitySlider.isContinuous = true
        opacitySlider.autoresizingMask = []   // fixed width — does not stretch with window

        [closeBtn, changeBtn, removeBtn, opacityLabel, opacitySlider]
            .forEach { ribbon.addSubview($0) }

        return ribbon
    }

    // MARK: - Toolbar Ribbon Actions

    @objc private func closeOverlay() {
        window?.orderOut(nil)
        // Does NOT quit the app — matches "Toggle Visibility" semantics
    }

    @objc private func changeImageAction() {
        clearAndReopen()
    }

    @objc private func removeImageAction() {
        guard canvasView.image != nil else { return }   // no-op if already in empty state
        canvasView.image = nil
        window?.orderOut(nil)
        showWelcomeWindow()   // returns to initial empty/placeholder state
    }

    @objc private func windowOpacityChanged(_ sender: NSSlider) {
        window?.alphaValue = CGFloat(sender.doubleValue)
    }
}

// MARK: - NSWindowDelegate

extension OverlayWindowController: NSWindowDelegate {
    // No delegate methods needed — ribbon is embedded and resizes via autoresizingMask.
    // Conformance is retained because window.delegate = self is set in init.
}

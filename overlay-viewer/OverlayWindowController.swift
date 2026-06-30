import Cocoa
import UniformTypeIdentifiers


// MARK: - OverlayContainerView

final class OverlayContainerView: NSView {
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.borderWidth = 0.5
    }
    
}


// MARK: - ToolbarRibbonView

final class ToolbarRibbonView: NSVisualEffectView {

    static let height: CGFloat = 36

    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        material = .menu
        blendingMode = .behindWindow
        state = .active
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 8
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }
}


// MARK: - OverlayWindowController

final class OverlayWindowController: NSWindowController {

    private let canvasView = ImageCanvasView()
    private var toolbarRibbon: ToolbarRibbonView?
    private var welcomeController: WelcomeWindowController?
    private var keyMonitor: Any?
    private var opacitySlider: NSSlider?
    private var settingsPopover: NSPopover?
    private var resizer: ResizeHandleView?

    private enum ContentMode { case none, image }
    private var contentMode: ContentMode = .none

    private static let opacityKey          = "overlay.opacity"
    private static let lastImageKey        = "overlay.lastImageURL"
    private static let lastFigmaFileKeyKey = "overlay.lastFigmaFileKey"
    private static let lastFigmaNodeIDKey  = "overlay.lastFigmaNodeID"
    private static let customWidthKey      = "overlay.customWidth"
    private static let customHeightKey     = "overlay.customHeight"
    private static let minWindowSize       = NSSize(width: 400, height: ToolbarRibbonView.height + 60)

    // MARK: - Init

    convenience init() {
        let window = OverlayWindow()
        self.init(window: window)

        let container = OverlayContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400)
        )
        container.autoresizingMask = [.width, .height]

        let ribbon = buildToolbarRibbon()
        ribbon.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(canvasView)
        container.addSubview(ribbon)

        NSLayoutConstraint.activate([
            ribbon.topAnchor.constraint(equalTo: container.topAnchor),
            ribbon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            ribbon.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ribbon.heightAnchor.constraint(equalToConstant: ToolbarRibbonView.height),

            canvasView.topAnchor.constraint(equalTo: ribbon.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Resize handle overlay (must be added LAST so it's on top) — gives the
        // borderless overlay window real edge/corner drag-to-resize, not just
        // the gear icon's numeric popover.
        let resizer = ResizeHandleView(minSize: Self.minWindowSize, frame: container.bounds)
        resizer.autoresizingMask = [.width, .height]
        resizer.chromeHeight = ToolbarRibbonView.height
        container.addSubview(resizer)
        self.resizer = resizer

        window.contentView = container
        window.delegate = self
        window.minSize = Self.minWindowSize
        window.setFrameAutosaveName("OverlayWindowFrame")
        if !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            window.center()
        }

        self.toolbarRibbon = ribbon

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch (event.keyCode, event.modifierFlags.contains(.command)) {
            case (53, _):    // Escape
                self.window?.orderOut(nil)
                return nil
            case (31, true): // Cmd+O
                self.presentOpenPanelOrWelcome()
                return nil
            default:
                return event
            }
        }
    }

    deinit {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Public API

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // The overlay window sits at .floating level to stay always-on-top;
        // NSOpenPanel defaults to .normal, which is BELOW that, so without
        // this it visibly opens underneath the overlay instead of in front.
        panel.level = .modalPanel

        NSApp.activate()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.load(imageURL: url)
        }
    }

    func showOpenPanelIfNeeded() {
        if contentMode == .none {
            presentOpenPanel()
        }
    }

    func showWelcomeWindow() {
        NSLog("3. showWelcomeWindow called")                         // >>> CHANGED

        if welcomeController == nil {
            let wc = WelcomeWindowController()
            wc.onImagePicked = { [weak self] url in
                self?.load(imageURL: url)
            }
            wc.onFigmaResourceLoaded = { [weak self] image, resource in
                self?.load(figmaImage: image, resource: resource)
            }
            welcomeController = wc
        }
        welcomeController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)                       // >>> CHANGED (moved earlier)
        welcomeController?.window?.makeKeyAndOrderFront(nil)
        welcomeController?.window?.orderFrontRegardless()

        NSLog("4. Window ordered front, isVisible: \(welcomeController?.window?.isVisible ?? false)") // >>> CHANGED
    }

    func presentOpenPanelOrWelcome() {
        if contentMode == .none {
            showWelcomeWindow()
        } else {
            presentOpenPanel()
        }
    }

    func clearAndReopen() {
        canvasView.image = nil
        contentMode = .none
        clearPersistedFigmaResource()
        window?.orderOut(nil)
        presentOpenPanel()
    }

    func toggleVisibility() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    @discardableResult
    func restoreLastImage() -> Bool {
        if let fileKey = UserDefaults.standard.string(forKey: Self.lastFigmaFileKeyKey),
           FigmaOAuthService.shared.isConnected {
            let nodeID = UserDefaults.standard.string(forKey: Self.lastFigmaNodeIDKey)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let image = try await FigmaAPIClient.shared.fetchRenderedImage(fileKey: fileKey, nodeID: nodeID)
                    self.load(
                        figmaImage: image,
                        resource: FigmaURLParser.Resource(fileKey: fileKey, nodeID: nodeID),
                        resetCustomSize: false
                    )
                } catch {
                    self.clearPersistedFigmaResource()
                    self.showWelcomeWindow()
                }
            }
            return true
        }
        guard let urlString = UserDefaults.standard.string(forKey: Self.lastImageKey),
              let url = URL(string: urlString),
              FileManager.default.fileExists(atPath: url.path) else { return false }
        load(imageURL: url, resetCustomSize: false)
        return true
    }

    // MARK: - Image loading

    private func load(imageURL: URL, resetCustomSize: Bool = true) {
        guard let image = NSImage(contentsOf: imageURL) else { return }
        welcomeController?.window?.orderOut(nil)
        canvasView.isHidden = false
        canvasView.image = image
        contentMode = .image
        clearPersistedFigmaResource()
        presentLoadedImage(image, resetCustomSize: resetCustomSize)
        UserDefaults.standard.set(imageURL.absoluteString, forKey: Self.lastImageKey)
    }

    // MARK: - Figma loading

    /// Renders a Figma file/node fetched via FigmaAPIClient (using the
    /// connected user's OAuth token) the same way as any other static image.
    func load(figmaImage image: NSImage, resource: FigmaURLParser.Resource, resetCustomSize: Bool = true) {
        welcomeController?.window?.orderOut(nil)
        canvasView.isHidden = false
        canvasView.image = image
        contentMode = .image
        UserDefaults.standard.removeObject(forKey: Self.lastImageKey)
        UserDefaults.standard.set(resource.fileKey, forKey: Self.lastFigmaFileKeyKey)
        if let nodeID = resource.nodeID {
            UserDefaults.standard.set(nodeID, forKey: Self.lastFigmaNodeIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastFigmaNodeIDKey)
        }
        presentLoadedImage(image, resetCustomSize: resetCustomSize)
    }

    /// `resetCustomSize` is true for any freshly user-opened image/file, so the
    /// window always fits (contains) the new content instead of reusing a custom
    /// size that was sized for a previous image's aspect ratio. It's false only
    /// when restoring the same image on relaunch, where keeping the saved size
    /// is the intended "persistent state" behavior.
    private func presentLoadedImage(_ image: NSImage, resetCustomSize: Bool) {
        resizer?.aspectRatio = image.size.width / image.size.height

        if resetCustomSize {
            UserDefaults.standard.removeObject(forKey: Self.customWidthKey)
            UserDefaults.standard.removeObject(forKey: Self.customHeightKey)
        }

        let savedW = UserDefaults.standard.double(forKey: Self.customWidthKey)
        let savedH = UserDefaults.standard.double(forKey: Self.customHeightKey)
        if savedW > 0 && savedH > 0 {
            window?.setContentSize(NSSize(width: savedW, height: savedH))
        } else {
            let maxDimension: CGFloat = 800
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
            let windowSize = NSSize(
                width: image.size.width * scale,
                height: image.size.height * scale + ToolbarRibbonView.height
            )
            window?.setContentSize(windowSize)
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()

        let savedOpacity = persistedOpacity
        window?.alphaValue = 1.0
        canvasView.alphaValue = CGFloat(savedOpacity)
        opacitySlider?.doubleValue = savedOpacity
    }

    private func clearPersistedFigmaResource() {
        UserDefaults.standard.removeObject(forKey: Self.lastFigmaFileKeyKey)
        UserDefaults.standard.removeObject(forKey: Self.lastFigmaNodeIDKey)
    }

    // MARK: - Persistence

    private var persistedOpacity: Double {
        get {
            let v = UserDefaults.standard.double(forKey: Self.opacityKey)
            return v == 0 ? 1.0 : v.clamped(to: 0.1...1.0)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.opacityKey) }
    }

    // MARK: - Build Toolbar Ribbon

    private func buildToolbarRibbon() -> ToolbarRibbonView {
        let ribbon = ToolbarRibbonView()

        let closeBtn = NSButton()
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close overlay")
        closeBtn.title = ""
        closeBtn.bezelStyle = .circular
        closeBtn.isBordered = false
        closeBtn.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.target = self
        closeBtn.action = #selector(closeOverlay)

        let changeBtn = NSButton()
        changeBtn.title = "Change…"
        changeBtn.bezelStyle = .rounded
        changeBtn.isBordered = false
        changeBtn.contentTintColor = .white
        changeBtn.font = .systemFont(ofSize: 11)
        changeBtn.translatesAutoresizingMaskIntoConstraints = false
        changeBtn.target = self
        changeBtn.action = #selector(changeImageAction)

        let removeBtn = NSButton()
        removeBtn.title = "Remove"
        removeBtn.bezelStyle = .rounded
        removeBtn.isBordered = false
        removeBtn.contentTintColor = .white
        removeBtn.font = .systemFont(ofSize: 11)
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        removeBtn.target = self
        removeBtn.action = #selector(removeImageAction)

        let opacityLabel = NSTextField(labelWithString: "Opacity")
        opacityLabel.textColor = .white
        opacityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        opacityLabel.translatesAutoresizingMaskIntoConstraints = false

        let slider = NSSlider(
            value: 1.0, minValue: 0.1, maxValue: 1.0,
            target: self, action: #selector(windowOpacityChanged(_:))
        )
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        self.opacitySlider = slider

        let settingsBtn = NSButton()
        settingsBtn.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsBtn.title = ""
        settingsBtn.bezelStyle = .circular
        settingsBtn.isBordered = false
        settingsBtn.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false
        settingsBtn.target = self
        settingsBtn.action = #selector(openSettingsAction(_:))

        // A zero-intrinsic-size view that soaks up all the slack between the
        // button group and the opacity controls — the "space-between" half
        // of a flex layout, AppKit-style.
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // One stack instead of two independently-pinned ones: with two
        // separate stacks there was no constraint stopping them from
        // overlapping once the window got narrow. A single stack lets
        // AppKit auto-hide the least essential controls (lowered via
        // setClippingResistancePriority below) before anything can collide.
        let toolbarStack = NSStackView(views: [
            closeBtn, changeBtn, removeBtn, settingsBtn, spacer, opacityLabel, slider,
        ])
        toolbarStack.orientation = .horizontal
        toolbarStack.spacing = 8
        toolbarStack.alignment = .centerY
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        // Hide order when space runs out, least important first: the
        // opacity label's text, then the slider itself. The four core
        // buttons stay visible at any width down to window.minSize.
        toolbarStack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        toolbarStack.setVisibilityPriority(.init(rawValue: 200), for: opacityLabel)
        toolbarStack.setVisibilityPriority(.init(rawValue: 400), for: slider)

        ribbon.addSubview(toolbarStack)

        NSLayoutConstraint.activate([
            closeBtn.widthAnchor.constraint(equalToConstant: 22),
            closeBtn.heightAnchor.constraint(equalToConstant: 22),
            settingsBtn.widthAnchor.constraint(equalToConstant: 22),
            settingsBtn.heightAnchor.constraint(equalToConstant: 22),
            slider.widthAnchor.constraint(equalToConstant: 120),

            toolbarStack.leadingAnchor.constraint(equalTo: ribbon.leadingAnchor, constant: 10),
            toolbarStack.trailingAnchor.constraint(equalTo: ribbon.trailingAnchor, constant: -10),
            toolbarStack.centerYAnchor.constraint(equalTo: ribbon.centerYAnchor),
        ])

        return ribbon
    }

    // MARK: - Size Settings

    private func reapplyImageSize() {
        guard contentMode == .image, let image = canvasView.image else { return }
        let maxDimension: CGFloat = 800
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        let size = NSSize(
            width:  image.size.width  * scale,
            height: image.size.height * scale + ToolbarRibbonView.height
        )
        window?.setContentSize(size)
        window?.center()
    }

    @objc private func openSettingsAction(_ sender: NSButton) {
        if settingsPopover == nil {
            let vc = SizeSettingsViewController()
            vc.onApply = { [weak self] w, h in
                guard let self, let window = self.window else { return }
                let clamped = NSSize(width: max(Self.minWindowSize.width, w), height: max(Self.minWindowSize.height, h))
                window.setContentSize(clamped)
                window.center()
                UserDefaults.standard.set(Double(clamped.width),  forKey: Self.customWidthKey)
                UserDefaults.standard.set(Double(clamped.height), forKey: Self.customHeightKey)
                self.settingsPopover?.close()
            }
            vc.onReset = { [weak self] in
                guard let self else { return }
                UserDefaults.standard.removeObject(forKey: Self.customWidthKey)
                UserDefaults.standard.removeObject(forKey: Self.customHeightKey)
                self.reapplyImageSize()
                self.settingsPopover?.close()
            }
            let pop = NSPopover()
            pop.contentViewController = vc
            pop.behavior = .transient
            pop.contentSize = NSSize(width: 240, height: 110)
            settingsPopover = pop
        }
        if let vc = settingsPopover?.contentViewController as? SizeSettingsViewController,
           let size = window?.contentView?.frame.size {
            vc.currentSize = size
        }
        settingsPopover?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    // MARK: - Actions

    @objc private func closeOverlay() {
        window?.orderOut(nil)
    }

    @objc private func changeImageAction() {
        clearAndReopen()
    }

    @objc private func removeImageAction() {
        guard contentMode != .none else { return }
        canvasView.image = nil
        contentMode = .none
        clearPersistedFigmaResource()
        window?.orderOut(nil)
        showWelcomeWindow()
    }

    @objc private func windowOpacityChanged(_ sender: NSSlider) {
        let v = CGFloat(sender.doubleValue)
        canvasView.alphaValue = v
        persistedOpacity = sender.doubleValue
    }
}


// MARK: - NSWindowDelegate

extension OverlayWindowController: NSWindowDelegate {}


// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

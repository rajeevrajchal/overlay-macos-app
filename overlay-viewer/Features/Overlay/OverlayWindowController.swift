import Cocoa
import Combine
import SwiftUI
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
        // A medium-gray, mostly-opaque hairline so the app's edge reads clearly
        // against both light and dark backdrops (a faint white line vanishes on
        // light desktops).
        layer?.borderColor = NSColor(white: 0.6, alpha: 0.85).cgColor
        layer?.borderWidth = 1.0
    }
    
}


// MARK: - OverlayWindowController

final class OverlayWindowController: NSWindowController {

    private let environment: AppEnvironment
    private let gridView = CanvasGridView()
    private let canvasView = ImageCanvasView()
    private let controlsViewModel = OverlayControlsViewModel()
    private var welcomeController: WelcomeWindowController?
    private var keyMonitor: Any?
    private var resizer: ResizeHandleView?
    private var cancellables = Set<AnyCancellable>()

    private enum ContentMode { case none, image }
    private var contentMode: ContentMode = .none

    private static let lastImageKey        = "overlay.lastImageURL"
    private static let customWidthKey      = "overlay.customWidth"
    private static let customHeightKey     = "overlay.customHeight"
    // Deliberately small so the overlay can be shrunk to a corner thumbnail —
    // the toolbar degrades gracefully at narrow widths, and the size gear allows
    // exact dimensions.
    private static let minWindowSize       = NSSize(width: 220, height: OverlayToolbar.height + 30)

    // MARK: - Init

    init(environment: AppEnvironment) {
        self.environment = environment
        let window = OverlayWindow()
        super.init(window: window)

        let container = OverlayContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400)
        )
        container.autoresizingMask = [.width, .height]

        // The whole toolbar is one self-contained SwiftUI component: it carries
        // its own vibrant material, height, and divider, so it just needs
        // hosting and pinning — no AppKit wrapper view.
        controlsViewModel.onRemove = { [weak self] in self?.removeImage() }
        controlsViewModel.onApplyCustomSize = { [weak self] width, height in
            self?.applyCustomSize(width: width, height: height)
        }
        controlsViewModel.onResetSize = { [weak self] in
            self?.resetToImageFit()
        }
        let toolbar = NSHostingView(rootView: OverlayToolbar(viewModel: controlsViewModel))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        gridView.translatesAutoresizingMaskIntoConstraints = false

        // Bottom-to-top z-order: fixed-alpha grid, then the image (the only
        // layer that obeys the opacity slider), then the always-opaque toolbar.
        container.addSubview(gridView)
        container.addSubview(canvasView)
        container.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: OverlayToolbar.height),

            canvasView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Grid fills the same content area as the image, sitting behind it.
            gridView.topAnchor.constraint(equalTo: canvasView.topAnchor),
            gridView.leadingAnchor.constraint(equalTo: canvasView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: canvasView.trailingAnchor),
            gridView.bottomAnchor.constraint(equalTo: canvasView.bottomAnchor),
        ])

        // Resize handle overlay (must be added LAST so it's on top) — gives the
        // borderless overlay window real edge/corner drag-to-resize, not just
        // the gear icon's numeric popover.
        let resizer = ResizeHandleView(minSize: Self.minWindowSize, frame: container.bounds)
        resizer.autoresizingMask = [.width, .height]
        resizer.chromeHeight = OverlayToolbar.height
        container.addSubview(resizer)
        self.resizer = resizer

        window.contentView = container
        window.delegate = self
        window.minSize = Self.minWindowSize
        window.setFrameAutosaveName("OverlayWindowFrame")
        if !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
            window.center()
        }

        // The control bar owns opacity; mirror every change onto the image
        // pixels (content-only fade, not the whole window) and persist it.
        // `@Published` replays its current value on subscribe, so this also
        // sets the initial opacity. No `.receive(on: RunLoop.main)` hop here on
        // purpose: the view model is already @MainActor, and a RunLoop.main
        // scheduler only fires in the default mode, which is starved while the
        // slider is being dragged (mouse tracking runs in event-tracking mode).
        // Updating synchronously keeps the canvas in lock-step with the thumb.
        controlsViewModel.$opacity
            .sink { [weak self] value in
                self?.canvasView.contentOpacity = CGFloat(value)
                self?.controlsViewModel.persist()
            }
            .store(in: &cancellables)

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

    required init?(coder: NSCoder) { fatalError() }

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
            let wc = WelcomeWindowController(environment: environment)
            wc.onImagePicked = { [weak self] url in
                self?.load(imageURL: url)
            }
            wc.onProviderImageLoaded = { [weak self] image in
                self?.load(providerImage: image)
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
        environment.figmaProvider.clearLastImage()
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
        if environment.figmaProvider.hasPersistedImage {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if let image = try await self.environment.figmaProvider.restoreLastImage() {
                        self.load(providerImage: image, resetCustomSize: false)
                        return
                    }
                } catch {
                    // fall through to clear + show welcome below
                }
                self.environment.figmaProvider.clearLastImage()
                self.showWelcomeWindow()
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
        environment.figmaProvider.clearLastImage()
        presentLoadedImage(image, resetCustomSize: resetCustomSize)
        UserDefaults.standard.set(imageURL.absoluteString, forKey: Self.lastImageKey)
    }

    /// Presents an image fetched through a DesignSourceProviding (Figma
    /// today), the same way as any other static image. The provider itself
    /// already persisted whatever it needs to restore this on relaunch.
    func load(providerImage image: NSImage, resetCustomSize: Bool = true) {
        welcomeController?.window?.orderOut(nil)
        canvasView.isHidden = false
        canvasView.image = image
        contentMode = .image
        UserDefaults.standard.removeObject(forKey: Self.lastImageKey)
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
            window?.setContentSize(imageFitContentSize(image))
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()

        window?.alphaValue = 1.0
        // Opacity is mirrored onto the canvas by the controlsViewModel
        // subscription set up in init; nothing to do here.
        syncContentSize()
    }

    /// The content size that fits (contains) the image at up to 1× scale, plus
    /// the toolbar strip.
    private func imageFitContentSize(_ image: NSImage) -> NSSize {
        let maxDimension: CGFloat = 800
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)
        return NSSize(
            width: image.size.width * scale,
            height: image.size.height * scale + OverlayToolbar.height
        )
    }

    // MARK: - Custom size (gear popover)

    private func applyCustomSize(width: CGFloat, height: CGFloat) {
        guard let window else { return }
        let size = NSSize(
            width: max(Self.minWindowSize.width, width),
            height: max(Self.minWindowSize.height, height)
        )
        window.setContentSize(size)
        UserDefaults.standard.set(Double(size.width), forKey: Self.customWidthKey)
        UserDefaults.standard.set(Double(size.height), forKey: Self.customHeightKey)
        syncContentSize()
    }

    private func resetToImageFit() {
        UserDefaults.standard.removeObject(forKey: Self.customWidthKey)
        UserDefaults.standard.removeObject(forKey: Self.customHeightKey)
        guard let window, contentMode == .image, let image = canvasView.image else { return }
        window.setContentSize(imageFitContentSize(image))
        window.center()
        syncContentSize()
    }

    /// Keep the view model's `contentSize` in step with the live window so the
    /// size popover pre-fills current dimensions.
    private func syncContentSize() {
        if let size = window?.contentView?.frame.size {
            controlsViewModel.contentSize = size
        }
    }

    // MARK: - Actions

    private func removeImage() {
        guard contentMode != .none else { return }
        canvasView.image = nil
        contentMode = .none
        environment.figmaProvider.clearLastImage()
        window?.orderOut(nil)
        showWelcomeWindow()
    }
}


// MARK: - NSWindowDelegate

extension OverlayWindowController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        syncContentSize()
    }
}

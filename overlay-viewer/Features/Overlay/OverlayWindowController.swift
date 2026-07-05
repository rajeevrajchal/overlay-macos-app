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

        // Aspect-lock toggle: mirror onto the canvas draw mode (fit vs stretch)
        // and the window's interactive resize constraint (ratio-locked vs
        // free-form), then persist. Kept in one place so the two never drift.
        controlsViewModel.$aspectLocked
            .sink { [weak self] _ in
                self?.applyAspectLock()
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

    /// Attempts to restore the last-shown image. Returns `true` ONLY when it
    /// actually put a window on screen — the launch sequence relies on a `false`
    /// return to fall back to the welcome screen, so this must never claim
    /// success it didn't deliver. (The Figma branch returns `true` eagerly but
    /// owns its own welcome fallback inside the async task.)
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
        // `fileExists` passing doesn't guarantee the file is *readable* — a
        // sandboxed app loses access to arbitrary paths across launches, so the
        // decode can still fail. If it does, drop the stale key and report
        // failure so the caller shows the welcome screen instead of nothing.
        guard load(imageURL: url, resetCustomSize: false) else {
            UserDefaults.standard.removeObject(forKey: Self.lastImageKey)
            return false
        }
        return true
    }

    // MARK: - Image loading

    /// Returns `true` when the image decoded and a window was presented; `false`
    /// if the file couldn't be read/decoded, so callers can fall back.
    @discardableResult
    private func load(imageURL: URL, resetCustomSize: Bool = true) -> Bool {
        guard let image = NSImage(contentsOf: imageURL) else { return false }
        welcomeController?.window?.orderOut(nil)
        canvasView.isHidden = false
        canvasView.image = image
        contentMode = .image
        environment.figmaProvider.clearLastImage()
        presentLoadedImage(image, resetCustomSize: resetCustomSize)
        UserDefaults.standard.set(imageURL.absoluteString, forKey: Self.lastImageKey)
        return true
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
        applyAspectLock()

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

    /// Push the current aspect-lock choice down to the two views that enforce
    /// it: the canvas (fit vs stretch draw) and the resize handle (ratio-locked
    /// vs free-form window resize). In free-form mode the resizer ratio is
    /// cleared so any edge can be dragged independently; in locked mode it's the
    /// live image's ratio so the window never letterboxes. No-op'd cleanly when
    /// no image is loaded.
    private func applyAspectLock() {
        let locked = controlsViewModel.aspectLocked
        canvasView.aspectLocked = locked
        if locked, let image = canvasView.image, image.size.height > 0 {
            resizer?.aspectRatio = image.size.width / image.size.height
        } else {
            resizer?.aspectRatio = nil
        }
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

    /// Constrain interactive resize to the image's aspect ratio while aspect-lock
    /// is on, so dragging any window edge scales the image proportionally — the
    /// automatic "Shift-drag" behavior — instead of letting the window drift to a
    /// mismatched shape that would gutter the fitted image. This covers the
    /// system's built-in edge resize (`.resizable`), which bypasses the custom
    /// `ResizeHandleView`; the handle enforces the same ratio for its own drags.
    /// In free-form mode we return the proposed size untouched (deliberate
    /// stretch). Programmatic `setContentSize` (the numeric size popover) doesn't
    /// route through here, so that manual override still works.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard controlsViewModel.aspectLocked,
              contentMode == .image,
              let image = canvasView.image,
              image.size.width > 0, image.size.height > 0 else { return frameSize }

        let ratio = image.size.width / image.size.height
        let chrome = OverlayToolbar.height            // toolbar strip isn't part of the image area
        let current = sender.frame.size

        // Drive from whichever dimension the user moved more; derive the other so
        // width : (height - toolbar) stays equal to the image's ratio.
        var width = frameSize.width
        var height = frameSize.height
        if abs(frameSize.width - current.width) >= abs(frameSize.height - current.height) {
            height = width / ratio + chrome
        } else {
            width = (height - chrome) * ratio
        }

        // Never propose below the window minimum on either axis.
        let minS = Self.minWindowSize
        if width < minS.width  { width = minS.width;  height = width / ratio + chrome }
        if height < minS.height { height = minS.height; width = (height - chrome) * ratio }

        return NSSize(width: width, height: height)
    }

    /// The window's own close control (red traffic light / ⌘W) means "I'm done"
    /// — fully quit the app, unlike Toggle Visibility (⌘H), which only hides via
    /// `orderOut`. `windowShouldClose` fires solely on user-initiated closes, so
    /// it never re-enters while `terminate` is tearing windows down.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApplication.shared.terminate(nil)
        return false
    }
}

import Cocoa
import SwiftUI
import UniformTypeIdentifiers


// MARK: - WelcomeWindow

final class WelcomeWindow: NSWindow {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // A real title bar — so the system draws real traffic lights with their
        // built-in hover, cursor, ⌘W, and VoiceOver support — but transparent
        // and with content extending edge-to-edge underneath, preserving the
        // borderless overlay look.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 260, height: 360)
        collectionBehavior = [.canJoinAllSpaces, .transient]

        // The red close button is the "X" replacement, for free. Minimize/zoom
        // don't fit an always-on-top reference panel, so hide them deliberately.
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}


// MARK: - FrostedEffectView

private final class FrostedEffectView: NSVisualEffectView {
    override func layout() {
        super.layout()
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }
}


// MARK: - WelcomeWindowController

/// Hosts the SwiftUI `WelcomeView` inside the app's frosted, borderless,
/// always-on-top window. AppKit still owns the things SwiftUI can't do here —
/// the floating window itself, the always-on-top file picker, and delivering a
/// picked `URL`/`NSImage` back to the overlay — while all layout, styling, and
/// accessibility live in the SwiftUI layer driven by `WelcomeViewModel`.
final class WelcomeWindowController: NSWindowController {

    var onImagePicked: ((URL) -> Void)?
    var onProviderImageLoaded: ((NSImage) -> Void)?

    private let environment: AppEnvironment
    private let viewModel: WelcomeViewModel
    private var isPresenting = false

    init(environment: AppEnvironment) {
        self.environment = environment
        self.viewModel = WelcomeViewModel(source: environment.figmaProvider)
        let win = WelcomeWindow()
        super.init(window: win)

        wireViewModelIntents()
        buildUI(in: win)
        win.delegate = self
        win.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Intent wiring

    private func wireViewModelIntents() {
        viewModel.onBrowseRequested = { [weak self] in
            self?.presentOpenPanel()
        }
        viewModel.onFileDropped = { [weak self] url in
            self?.window?.orderOut(nil)
            self?.onImagePicked?(url)
        }
        viewModel.onProviderImageLoaded = { [weak self] image in
            self?.window?.orderOut(nil)
            self?.onProviderImageLoaded?(image)
        }
    }

    // MARK: - UI Construction

    private func buildUI(in win: NSWindow) {
        let effect = FrostedEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        win.contentView = effect

        let host = NSHostingView(rootView: WelcomeView(viewModel: viewModel))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        // Resize handle overlay (must be added LAST so it's on top).
        let resizer = ResizeHandleView(minSize: win.minSize, frame: effect.bounds)
        resizer.autoresizingMask = [.width, .height]
        effect.addSubview(resizer)
    }

    // MARK: - Always-on-top file picker

    func presentOpenPanel() {
        guard !isPresenting else { return }
        isPresenting = true

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // WelcomeWindow is .floating level to stay always-on-top; NSOpenPanel
        // defaults to .normal (below that), so it would otherwise open visibly
        // behind this window instead of in front of it.
        panel.level = .modalPanel
        NSApp.activate()
        panel.begin { [weak self] response in
            self?.isPresenting = false
            guard response == .OK, let url = panel.url else { return }
            self?.window?.orderOut(nil)
            self?.onImagePicked?(url)
        }
    }
}


// MARK: - NSWindowDelegate

extension WelcomeWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // Activate so keyboard events (typing, Cmd+V) reach the SwiftUI text
        // field, and re-derive connection state (creds may have changed while
        // the browser auth sheet was up).
        NSApp.activate()
        viewModel.refreshConnectionState()
    }

    /// Closing the start panel means "I'm done" — quit the whole app, the same
    /// as closing the overlay. (Hiding for later is Toggle Visibility / ⌘H,
    /// which uses `orderOut` and never reaches this method.)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApplication.shared.terminate(nil)
        return false
    }
}

import Cocoa
import UniformTypeIdentifiers


// MARK: - WelcomeWindow

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


// MARK: - FrostedEffectView

private final class FrostedEffectView: NSVisualEffectView {
    override func layout() {
        super.layout()
        layer?.cornerRadius = 12
    }
}


// MARK: - WelcomeWindowController

final class WelcomeWindowController: NSWindowController {

    var onImagePicked: ((URL) -> Void)?
    var onProviderImageLoaded: ((NSImage) -> Void)?
    private let environment: AppEnvironment
    private var isPresenting = false
    private var figmaField: NSTextField?
    private var figmaOpenButton: NSButton?
    private var figmaErrorLabel: NSTextField?
    private let connectView = FigmaConnectView()
    private static let figmaHandleKey = "overlay.figmaHandle"

    init(environment: AppEnvironment) {
        self.environment = environment
        let win = WelcomeWindow()
        super.init(window: win)
        buildUI(in: win)
        win.delegate = self
        win.center()
        refreshConnectState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Construction

    private func buildUI(in win: NSWindow) {
        // 1. Root frosted-glass container
        let effect = FrostedEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 500))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        win.contentView = effect

        // 2. Ribbon (top strip, 40pt tall)
        let ribbonHeight: CGFloat = 40
        let ribbon = RibbonView()
        ribbon.translatesAutoresizingMaskIntoConstraints = false

        let closeBtn = NSButton()
        closeBtn.bezelStyle = .circular
        closeBtn.title = "\u{00D7}"
        closeBtn.font = .systemFont(ofSize: 14, weight: .bold)
        closeBtn.contentTintColor = .white
        closeBtn.isBordered = false
        closeBtn.target = self
        closeBtn.action = #selector(closeWelcome)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        ribbon.addSubview(closeBtn)
        effect.addSubview(ribbon)

        NSLayoutConstraint.activate([
            ribbon.topAnchor.constraint(equalTo: effect.topAnchor),
            ribbon.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            ribbon.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            ribbon.heightAnchor.constraint(equalToConstant: ribbonHeight),

            closeBtn.widthAnchor.constraint(equalToConstant: 24),
            closeBtn.heightAnchor.constraint(equalToConstant: 24),
            closeBtn.leadingAnchor.constraint(equalTo: ribbon.leadingAnchor, constant: 8),
            closeBtn.centerYAnchor.constraint(equalTo: ribbon.centerYAnchor),
        ])

        // 3. Body (fills space below ribbon)
        let body = ClickableBodyView()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.onClicked = { [weak self] in self?.presentOpenPanel() }
        body.registerForDraggedTypes([.fileURL])
        body.onFilesDropped = { [weak self] urls in
            guard let url = urls.first else { return }
            self?.window?.orderOut(nil)
            self?.onImagePicked?(url)
        }

        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppLogo")
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Click to open an image")
        label.alignment = .center
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        let dragLabel = NSTextField(labelWithString: "or drag an image here")
        dragLabel.alignment = .center
        dragLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        dragLabel.font = .systemFont(ofSize: 11)
        dragLabel.translatesAutoresizingMaskIntoConstraints = false

        // Figma URL section
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        connectView.translatesAutoresizingMaskIntoConstraints = false
        connectView.onConnectTapped = { [weak self] in self?.connectFigma() }
        connectView.onDisconnectTapped = { [weak self] in self?.disconnectFigma() }

        let figmaPrompt = NSTextField(labelWithString: "Or paste a Figma URL")
        figmaPrompt.alignment = .center
        figmaPrompt.textColor = NSColor.white.withAlphaComponent(0.55)
        figmaPrompt.font = .systemFont(ofSize: 11)
        figmaPrompt.translatesAutoresizingMaskIntoConstraints = false

        let figmaInput = NSTextField()
        figmaInput.placeholderString = "https://figma.com/design/…"
        figmaInput.font = .systemFont(ofSize: 11)
        figmaInput.isEditable = true
        figmaInput.isSelectable = true
        figmaInput.target = self
        figmaInput.action = #selector(openFigmaURL)
        figmaInput.translatesAutoresizingMaskIntoConstraints = false
        self.figmaField = figmaInput

        let figmaBtn = NSButton(title: "Open", target: self, action: #selector(openFigmaURL))
        figmaBtn.bezelStyle = .rounded
        figmaBtn.translatesAutoresizingMaskIntoConstraints = false
        self.figmaOpenButton = figmaBtn

        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.alignment = .center
        errorLabel.textColor = NSColor.systemOrange
        errorLabel.font = .systemFont(ofSize: 10)
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        self.figmaErrorLabel = errorLabel

        body.addSubview(iconView)
        body.addSubview(label)
        body.addSubview(dragLabel)
        body.addSubview(separator)
        body.addSubview(connectView)
        body.addSubview(figmaPrompt)
        body.addSubview(figmaInput)
        body.addSubview(figmaBtn)
        body.addSubview(errorLabel)
        effect.addSubview(body)

        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: ribbon.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: effect.bottomAnchor),

            // Icon shifted up (-30 vs old +20) to make room for the Figma section below
            iconView.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: body.centerYAnchor, constant: -30),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            label.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: body.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: body.trailingAnchor, constant: -20),

            dragLabel.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            dragLabel.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            dragLabel.leadingAnchor.constraint(greaterThanOrEqualTo: body.leadingAnchor, constant: 20),
            dragLabel.trailingAnchor.constraint(lessThanOrEqualTo: body.trailingAnchor, constant: -20),

            separator.topAnchor.constraint(equalTo: dragLabel.bottomAnchor, constant: 20),
            separator.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -20),

            connectView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            connectView.centerXAnchor.constraint(equalTo: body.centerXAnchor),
            connectView.leadingAnchor.constraint(greaterThanOrEqualTo: body.leadingAnchor, constant: 20),
            connectView.trailingAnchor.constraint(lessThanOrEqualTo: body.trailingAnchor, constant: -20),

            figmaPrompt.topAnchor.constraint(equalTo: connectView.bottomAnchor, constant: 12),
            figmaPrompt.centerXAnchor.constraint(equalTo: body.centerXAnchor),

            figmaInput.topAnchor.constraint(equalTo: figmaPrompt.bottomAnchor, constant: 8),
            figmaInput.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            figmaInput.trailingAnchor.constraint(equalTo: figmaBtn.leadingAnchor, constant: -8),

            figmaBtn.centerYAnchor.constraint(equalTo: figmaInput.centerYAnchor),
            figmaBtn.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -20),
            figmaBtn.widthAnchor.constraint(equalToConstant: 50),

            errorLabel.topAnchor.constraint(equalTo: figmaInput.bottomAnchor, constant: 6),
            errorLabel.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -20),
        ])

        // 4. Resize handle overlay (must be added LAST so it's on top)
        let resizer = ResizeHandleView(minSize: NSSize(width: 200, height: 300), frame: effect.bounds)
        resizer.autoresizingMask = [.width, .height]
        effect.addSubview(resizer)
    }

    // MARK: - Actions

    @objc private func closeWelcome() {
        window?.orderOut(nil)
    }

    @objc private func openFigmaURL() {
        clearFigmaError()
        let raw = (figmaField?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let url = URL(string: raw), environment.figmaProvider.canHandle(url: url) else {
            showFigmaError("That doesn't look like a Figma file URL.")
            return
        }
        guard environment.figmaProvider.isConnected else {
            showFigmaError("Connect Figma above first, then paste the URL.")
            return
        }

        figmaOpenButton?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.figmaOpenButton?.isEnabled = true }
            do {
                let image = try await self.environment.figmaProvider.fetchImage(from: url)
                self.window?.orderOut(nil)
                self.onProviderImageLoaded?(image)
            } catch {
                self.showFigmaError(error.localizedDescription)
            }
        }
    }

    // MARK: - Figma connect / disconnect

    private func connectFigma() {
        clearFigmaError()
        connectView.setState(.connecting)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let handle = try await self.environment.figmaProvider.connect()
                UserDefaults.standard.set(handle, forKey: Self.figmaHandleKey)
                self.connectView.setState(.connected(handle: handle))
            } catch FigmaOAuthError.userCancelled {
                self.connectView.setState(.disconnected)
            } catch {
                self.connectView.setState(.disconnected)
                self.showFigmaError(error.localizedDescription)
            }
        }
    }

    private func disconnectFigma() {
        environment.figmaProvider.disconnect()
        UserDefaults.standard.removeObject(forKey: Self.figmaHandleKey)
        connectView.setState(.disconnected)
    }

    private func refreshConnectState(animated: Bool) {
        if environment.figmaProvider.isConnected,
           let handle = UserDefaults.standard.string(forKey: Self.figmaHandleKey) {
            connectView.setState(.connected(handle: handle), animated: animated)
        } else {
            connectView.setState(.disconnected, animated: animated)
        }
    }

    private func showFigmaError(_ message: String) {
        figmaErrorLabel?.stringValue = message
    }

    private func clearFigmaError() {
        figmaErrorLabel?.stringValue = ""
    }

    func presentOpenPanel() {
        guard !isPresenting else { return }
        isPresenting = true

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // WelcomeWindow is .floating level to stay always-on-top; NSOpenPanel
        // defaults to .normal (below that), so it would otherwise open
        // visibly behind this window instead of in front of it.
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
        // Activate the app so keyboard events (typing, Cmd+V) reach the text field.
        // On macOS 14+, activate() works here because the user just clicked our window,
        // which provides the required interaction token.
        NSApp.activate()
        refreshConnectState(animated: false)
    }
}


// MARK: - RibbonView

private final class RibbonView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }
}


// MARK: - ClickableBodyView

private final class ClickableBodyView: NSView {
    var onClicked: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageURL(from: sender) != nil else { return [] }
        layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor.clear.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = NSColor.clear.cgColor
        guard let url = imageURL(from: sender) else { return false }
        onFilesDropped?([url])
        return true
    }

    private func imageURL(from info: NSDraggingInfo) -> URL? {
        guard let urls = info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self],
                         options: [.urlReadingFileURLsOnly: true]) as? [URL]
        else { return nil }
        return urls.first { NSImage(contentsOf: $0) != nil }
    }
}

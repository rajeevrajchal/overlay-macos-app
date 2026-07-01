import Cocoa

/// The "Connect Figma" CTA and its "Connected as X · Disconnect" counterpart,
/// crossfading between the two so the slot never shows both at once.
final class FigmaConnectView: NSView {

    enum State: Equatable {
        case disconnected
        case connecting
        case connected(handle: String)
    }

    var onConnectTapped: (() -> Void)?
    var onDisconnectTapped: (() -> Void)?

    private(set) var state: State = .disconnected

    private let connectButton = NSButton(title: "Connect Figma", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let connectStack = NSStackView()

    private let connectedLabel = NSTextField(labelWithString: "")
    private let disconnectButton = NSButton(title: "Disconnect", target: nil, action: nil)
    private let connectedStack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        connectButton.bezelStyle = .rounded
        connectButton.font = .systemFont(ofSize: 11, weight: .medium)
        connectButton.target = self
        connectButton.action = #selector(connectTapped)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        connectStack.orientation = .horizontal
        connectStack.spacing = 6
        connectStack.alignment = .centerY
        connectStack.translatesAutoresizingMaskIntoConstraints = false
        connectStack.addArrangedSubview(connectButton)
        connectStack.addArrangedSubview(spinner)

        connectedLabel.font = .systemFont(ofSize: 11, weight: .medium)
        connectedLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        connectedLabel.lineBreakMode = .byTruncatingTail

        disconnectButton.bezelStyle = .rounded
        disconnectButton.font = .systemFont(ofSize: 11)
        disconnectButton.target = self
        disconnectButton.action = #selector(disconnectTapped)

        connectedStack.orientation = .vertical
        connectedStack.spacing = 6
        connectedStack.alignment = .centerX
        connectedStack.translatesAutoresizingMaskIntoConstraints = false
        connectedStack.addArrangedSubview(connectedLabel)
        connectedStack.addArrangedSubview(disconnectButton)
        connectedStack.alphaValue = 0
        connectedStack.isHidden = true

        addSubview(connectStack)
        addSubview(connectedStack)

        NSLayoutConstraint.activate([
            connectStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            connectStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            connectStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            connectStack.topAnchor.constraint(equalTo: topAnchor),
            connectStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            connectedStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            connectedStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            connectedStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            connectedStack.topAnchor.constraint(equalTo: topAnchor),
            connectedStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func connectTapped() { onConnectTapped?() }
    @objc private func disconnectTapped() { onDisconnectTapped?() }

    func setState(_ newState: State, animated: Bool = true) {
        guard newState != state else { return }
        state = newState

        let showConnected: Bool
        switch newState {
        case .disconnected:
            showConnected = false
            connectButton.isEnabled = true
            spinner.stopAnimation(nil)
        case .connecting:
            showConnected = false
            connectButton.isEnabled = false
            spinner.startAnimation(nil)
        case .connected(let handle):
            showConnected = true
            connectedLabel.stringValue = "Connected as \(handle)"
            spinner.stopAnimation(nil)
        }

        let fadeIn = showConnected ? connectedStack : connectStack
        let fadeOut = showConnected ? connectStack : connectedStack

        guard animated else {
            fadeOut.isHidden = true
            fadeOut.alphaValue = 0
            fadeIn.isHidden = false
            fadeIn.alphaValue = 1
            return
        }

        fadeIn.isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fadeOut.animator().alphaValue = 0
            fadeIn.animator().alphaValue = 1
        }, completionHandler: { [weak fadeOut] in
            fadeOut?.isHidden = true
        })
    }
}

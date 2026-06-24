import Cocoa

/// A small, separate floating window holding the controls. Kept deliberately
/// independent of OverlayWindow so it is NEVER affected by the main window's
/// alphaValue — see OverlayWindowController for the reasoning.
final class ToolbarWindow: NSWindow {

    private weak var controller: OverlayWindowController?

    convenience init(controller: OverlayWindowController) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 96),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.controller = controller
        configure()
    }

    private func configure() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 280, height: 96))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        let windowOpacityLabel = label("Window")
        let windowOpacitySlider = makeSlider(action: #selector(windowOpacityChanged))
        windowOpacitySlider.doubleValue = 1.0

        let contentOpacityLabel = label("Image")
        let contentOpacitySlider = makeSlider(action: #selector(contentOpacityChanged))
        contentOpacitySlider.doubleValue = 1.0

        let clickThroughCheckbox = NSButton(checkboxWithTitle: "Click-through",
                                             target: self,
                                             action: #selector(clickThroughChanged(_:)))
        clickThroughCheckbox.frame = NSRect(x: 16, y: 8, width: 150, height: 18)
        clickThroughCheckbox.contentTintColor = .white

        windowOpacityLabel.frame = NSRect(x: 16, y: 70, width: 60, height: 16)
        windowOpacitySlider.frame = NSRect(x: 80, y: 68, width: 184, height: 20)
        contentOpacityLabel.frame = NSRect(x: 16, y: 40, width: 60, height: 16)
        contentOpacitySlider.frame = NSRect(x: 80, y: 38, width: 184, height: 20)

        [windowOpacityLabel, windowOpacitySlider, contentOpacityLabel, contentOpacitySlider, clickThroughCheckbox]
            .forEach { container.addSubview($0) }

        self.contentView = container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = .white
        field.font = .systemFont(ofSize: 11, weight: .medium)
        return field
    }

    private func makeSlider(action: Selector) -> NSSlider {
        let slider = NSSlider(value: 1.0, minValue: 0.05, maxValue: 1.0, target: self, action: action)
        slider.isContinuous = true
        return slider
    }

    @objc private func windowOpacityChanged(_ sender: NSSlider) {
        controller?.setWindowOpacity(CGFloat(sender.doubleValue))
    }

    @objc private func contentOpacityChanged(_ sender: NSSlider) {
        controller?.setContentOpacity(CGFloat(sender.doubleValue))
    }

    @objc private func clickThroughChanged(_ sender: NSButton) {
        controller?.setClickThrough(sender.state == .on)
    }

    override var canBecomeKey: Bool { true }
}

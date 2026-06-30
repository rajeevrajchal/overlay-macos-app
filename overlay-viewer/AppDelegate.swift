import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private lazy var overlayController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        if !overlayController.restoreLastImage() {
            overlayController.showWelcomeWindow()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled",
            accessibilityDescription: "Overlay Viewer"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Image…",       action: #selector(openImage),                    keyEquivalent: "o")
        // "Change Image…" removed — available via toolbar ribbon "Change…" button
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Toggle Visibility",  action: #selector(toggleVisibility),             keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit",               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openImage()        { overlayController.presentOpenPanelOrWelcome() }
    @objc private func toggleVisibility() { overlayController.toggleVisibility() }
}

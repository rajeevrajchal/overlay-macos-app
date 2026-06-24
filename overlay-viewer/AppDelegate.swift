import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let overlayController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // This is a "background utility" — no Dock icon, lives in the menu bar.
        // Set "Application is agent (UIElement)" = YES in Info.plist to fully hide the Dock icon.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        overlayController.showOpenPanelIfNeeded()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                                            accessibilityDescription: "Overlay Viewer")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Image…", action: #selector(openImage), keyEquivalent: "o")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Toggle Visibility", action: #selector(toggleVisibility), keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Wire menu actions to self so they can reach the controller.
        for item in menu.items {
            item.target = self
        }
        menu.items.first?.target = self
        statusItem.menu = menu
    }

    @objc private func openImage() {
        overlayController.presentOpenPanel()
    }

    @objc private func toggleVisibility() {
        overlayController.toggleVisibility()
    }
}

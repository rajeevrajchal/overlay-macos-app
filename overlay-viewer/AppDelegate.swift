import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private lazy var overlayController = OverlayWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("1. App launched")
        setupMainMenu()
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        NSLog("2. Status item created: \(statusItem != nil)")

        // Defer so the run loop is ready before we try to show/activate windows
        DispatchQueue.main.async {
            if !self.overlayController.restoreLastImage() {
                self.overlayController.showWelcomeWindow()
            }
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Toggle Visibility",  action: #selector(toggleVisibility),             keyEquivalent: "h")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit",               action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openImage()        { overlayController.presentOpenPanelOrWelcome() }
    @objc private func toggleVisibility() { overlayController.toggleVisibility() }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (macOS requires the first item to be the app menu)
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Overlay Tool",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu — without this, Cmd+C/V/X/A/Z cannot route through the
        // responder chain to the active NSTextField/NSTextView.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo",       action: Selector(("undo:")),             keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo",       action: Selector(("redo:")),             keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

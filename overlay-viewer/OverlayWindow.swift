import Cocoa

/// A borderless, floating window that:
///  - stays above all other application windows (.floating level)
///  - follows the user across every Space and every monitor (.canJoinAllSpaces)
///  - survives Space-switch animations without flicker (.stationary)
///  - shows above fullscreen apps too (.fullScreenAuxiliary)
///  - supports true alpha transparency in its content (isOpaque = false)
///  - can be dragged from anywhere, with no titlebar (isMovableByWindowBackground)
///
/// This class knows NOTHING about images. It is pure window plumbing.
/// That separation is what makes it reusable for any "always on top" tool later.
final class OverlayWindow: NSWindow {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        configureAsOverlay()
    }

    private func configureAsOverlay() {
        // --- Always-on-top ---
        // .floating sits above normal app windows. If you need it above
        // OTHER always-on-top utilities too, bump to a raw CGWindowLevel:
        // self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        self.level = .floating

        // --- Multi-Space / multi-monitor persistence ---
        self.collectionBehavior = [
            .canJoinAllSpaces,      // <- the property that makes it follow you across desktops
            .stationary,            // <- prevents flicker/disappearance during Space-switch animation
            .fullScreenAuxiliary,   // <- allowed to float over another app's fullscreen Space
            .ignoresCycle           // <- don't show up in Cmd+Tab / Mission Control window cycling
        ]

        // --- Transparency plumbing ---
        // Both of these MUST be set, or alphaValue changes do nothing visible.
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false

        // --- Free dragging, no titlebar ---
        self.isMovableByWindowBackground = true

        // --- Misc ---
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isReleasedWhenClosed = false
    }
}

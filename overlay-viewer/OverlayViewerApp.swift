import SwiftUI

@main
struct OverlayViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No WindowGroup — this is a menu-bar-driven utility app.
        // The overlay window is created and owned by AppDelegate -> OverlayWindowController.
        Settings {
            EmptyView()
        }
    }
}

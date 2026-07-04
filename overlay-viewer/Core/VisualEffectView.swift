import SwiftUI

/// Reusable SwiftUI bridge to `NSVisualEffectView`, so a SwiftUI view can sit on
/// real macOS vibrancy (and its automatic light/dark + behind-window adaptation)
/// instead of a flat fill. Lets self-contained components own their own material
/// rather than relying on an AppKit wrapper view around them.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

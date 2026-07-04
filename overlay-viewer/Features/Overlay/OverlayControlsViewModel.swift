import Combine
import SwiftUI

/// State for the overlay's floating control bar. Owns the one rule that matters
/// here — opacity, its bounds, and its persistence — and exposes button intents
/// as closures the AppKit host wires up. Unit-testable in isolation: no window,
/// no view, no timing.
@MainActor
final class OverlayControlsViewModel: ObservableObject {

    /// Content opacity of the overlaid image, 10%–100%. The lower bound is 0.1
    /// rather than 0 so the image can never fade to fully invisible (which reads
    /// as "the app broke") while still going faint enough for onion-skin tracing.
    @Published var opacity: Double

    /// Current overlay content size (window content area). The host keeps this in
    /// sync so the size-settings popover can pre-fill the live dimensions.
    @Published var contentSize: CGSize = CGSize(width: 600, height: 400)

    var onRemove: (() -> Void)?
    /// Apply a user-typed custom size (already floored to `minCustomSize`).
    var onApplyCustomSize: ((CGFloat, CGFloat) -> Void)?
    /// Discard the custom size and refit the window to the image.
    var onResetSize: (() -> Void)?

    static let range: ClosedRange<Double> = 0.1...1.0
    static let nudgeStep = 0.01
    /// A sanity floor for typed sizes; the host additionally clamps each
    /// dimension to the window's real minimum. Deliberately small so the overlay
    /// can be shrunk to a corner thumbnail.
    static let minCustomSize: CGFloat = 120

    private static let opacityKey = "overlay.opacity"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.opacityKey)
        self.opacity = stored == 0 ? 1.0 : stored.clamped(to: Self.range)
    }

    /// Whole-percent readout for the live label and VoiceOver value.
    var opacityPercent: Int { Int((opacity * 100).rounded()) }

    var accessibilityOpacityValue: String { "\(opacityPercent) percent" }

    /// Arrow-key / stepper nudge, clamped to `range`.
    func nudgeOpacity(by delta: Double) {
        opacity = (opacity + delta).clamped(to: Self.range)
    }

    /// Persist the current value. Called by the host after changes settle.
    func persist() {
        defaults.set(opacity, forKey: Self.opacityKey)
    }

    func requestRemove() { onRemove?() }

    /// Apply a custom size, flooring each dimension to `minCustomSize`.
    func applyCustomSize(width: CGFloat, height: CGFloat) {
        onApplyCustomSize?(
            Swift.max(Self.minCustomSize, width),
            Swift.max(Self.minCustomSize, height)
        )
    }

    func resetSize() { onResetSize?() }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

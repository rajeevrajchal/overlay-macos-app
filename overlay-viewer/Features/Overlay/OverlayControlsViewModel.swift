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

    var onRemove: (() -> Void)?

    static let range: ClosedRange<Double> = 0.1...1.0
    static let nudgeStep = 0.01

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
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

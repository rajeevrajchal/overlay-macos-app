import SwiftUI

/// The app's small, disciplined design vocabulary. One accent hue, a handful of
/// spacing steps, and a couple of corner radii — kept in one place so the
/// SwiftUI layer never reaches for ad-hoc magic numbers or a second accent.
///
/// Rule the whole UI obeys: the accent (a purple→blue gradient seeded from the
/// app icon) appears **only** on interactive or active states — primary
/// actions, active toggles, focus, drop targets. Static chrome stays neutral so
/// that "this is colorful" always means "this is actionable."
enum DesignTokens {

    // MARK: Accent

    /// Single accent hue, used for interactive/active states only.
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.95)

    /// The icon-seeded gradient, for primary CTAs and the active-drop halo.
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.55, green: 0.36, blue: 0.96),
                 Color(red: 0.30, green: 0.44, blue: 0.98)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
    }

    // MARK: Radii

    enum Radius {
        static let card: CGFloat = 10
        static let control: CGFloat = 7
    }

    // MARK: Neutral surfaces (over the window's frosted vibrancy)

    /// Subtle fill for cards so the window's blur still reads through them.
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
}

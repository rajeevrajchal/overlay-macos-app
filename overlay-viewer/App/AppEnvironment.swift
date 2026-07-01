import Cocoa

/// Composition root: the one place concrete services get instantiated and
/// wired together. Window/view controllers receive this through init
/// instead of reaching for `.shared` singletons directly, which makes it
/// straightforward to add a new DesignSourceProviding and to unit-test
/// controllers with fakes.
///
/// To add a new design source: implement DesignSourceProviding, add a
/// property for it here (mirroring `figmaProvider`), and append it to
/// `providers`.
final class AppEnvironment {
    let figmaProvider: FigmaProvider
    let providers: [DesignSourceProviding]

    init(figmaProvider: FigmaProvider = FigmaProvider()) {
        self.figmaProvider = figmaProvider
        self.providers = [figmaProvider]
    }
}

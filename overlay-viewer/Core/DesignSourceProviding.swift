import Cocoa

/// The extension point for adding a new place overlay images can come from.
/// Figma is the only conforming type today (see FigmaProvider); a future
/// Sketch/Zeplin/URL-image source just needs its own conforming type
/// registered in AppEnvironment.providers — nothing in the window/view layer
/// should reach for a provider's own singleton directly.
protocol DesignSourceProviding: AnyObject {
    var displayName: String { get }

    /// Whether this provider has the configuration it needs to function at
    /// all (e.g. OAuth client credentials), independent of whether a user
    /// has actually connected an account yet.
    var isConfigured: Bool { get }

    /// Whether a user is currently authenticated with this provider.
    var isConnected: Bool { get }

    /// Whether this provider has a previously-loaded image it can restore
    /// on relaunch without prompting the user again.
    var hasPersistedImage: Bool { get }

    /// Whether this provider recognizes the given URL as one of its own
    /// (e.g. a figma.com file URL).
    func canHandle(url: URL) -> Bool

    /// Runs this provider's full connect flow and returns a display handle
    /// for the connected account.
    func connect() async throws -> String

    /// Clears any stored credentials/session for this provider.
    func disconnect()

    /// Fetches a renderable image for a URL this provider has already
    /// confirmed it can handle, and persists it as the "last opened" image
    /// for this provider.
    func fetchImage(from url: URL) async throws -> NSImage

    /// Re-fetches the persisted "last opened" image, if any.
    func restoreLastImage() async throws -> NSImage?

    /// Clears whatever "last opened" state this provider persisted.
    func clearLastImage()
}

enum DesignSourceError: Error, LocalizedError {
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "This provider can't handle that URL."
        }
    }
}

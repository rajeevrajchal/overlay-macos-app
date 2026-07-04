import AppKit
import Combine

/// Single source of truth for the empty-state ("welcome") screen.
///
/// SOLID call-out: this type owns *welcome-screen behavior rules* and nothing
/// else. It talks to the outside world exclusively through the
/// `DesignSourceProviding` seam (Figma's OAuth/API live behind it), so it is
/// unit-testable with a mock source — no real network call and no
/// `ASWebAuthenticationSession` browser window ever appears in a test. The
/// window, the file-open panel, and turning a `URL`/`NSImage` into a live
/// overlay all belong to AppKit; this view model reaches them through the
/// intent closures below rather than importing that machinery.
@MainActor
final class WelcomeViewModel: ObservableObject {

    // MARK: Published state (what the SwiftUI view renders)

    @Published private(set) var connection: FigmaConnectionState = .disconnected
    @Published var figmaURLText: String = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isFetchingImage = false

    /// Whether Figma is configured at all (OAuth client creds present). When
    /// false the view hides the Figma card instead of dangling a dead button.
    let isFigmaConfigured: Bool

    // MARK: Intents routed out to the host controller

    var onCloseRequested: (() -> Void)?
    var onBrowseRequested: (() -> Void)?
    var onFileDropped: ((URL) -> Void)?
    var onProviderImageLoaded: ((NSImage) -> Void)?

    // MARK: Dependencies

    private let source: DesignSourceProviding
    private static let handleKey = "overlay.figmaHandle"

    init(source: DesignSourceProviding) {
        self.source = source
        self.isFigmaConfigured = source.isConfigured
        refreshConnectionState()
    }

    // MARK: Connection lifecycle

    /// Re-derives the connection state from persisted credentials — called on
    /// init and whenever the window regains key focus (creds can change while
    /// the browser auth sheet is up).
    func refreshConnectionState() {
        if source.isConnected, let handle = UserDefaults.standard.string(forKey: Self.handleKey) {
            connection = .connected(workspace: handle)
        } else if !connection.isConnecting {
            connection = .disconnected
        }
    }

    func connect() {
        errorMessage = nil
        connection = .connecting
        Task {
            do {
                let handle = try await source.connect()
                UserDefaults.standard.set(handle, forKey: Self.handleKey)
                connection = .connected(workspace: handle)
            } catch let error as FigmaOAuthError where error == .userCancelled {
                connection = .disconnected
            } catch {
                connection = .failed(reason: error.localizedDescription)
            }
        }
    }

    func disconnect() {
        source.disconnect()
        UserDefaults.standard.removeObject(forKey: Self.handleKey)
        figmaURLText = ""
        connection = .disconnected
    }

    // MARK: Entry points

    func requestBrowse() {
        errorMessage = nil
        onBrowseRequested?()
    }

    func requestClose() {
        onCloseRequested?()
    }

    /// Accepts a file URL dropped onto the window. Non-image URLs are ignored
    /// by the drop target itself, so anything arriving here is loadable.
    func handleDroppedFile(_ url: URL) {
        errorMessage = nil
        onFileDropped?(url)
    }

    func openFigmaURL() {
        errorMessage = nil
        let raw = figmaURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), source.canHandle(url: url) else {
            errorMessage = "That doesn't look like a Figma file URL."
            return
        }
        guard source.isConnected else {
            errorMessage = "Connect Figma first, then paste the URL."
            return
        }

        isFetchingImage = true
        Task {
            defer { isFetchingImage = false }
            do {
                let image = try await source.fetchImage(from: url)
                onProviderImageLoaded?(image)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// FigmaOAuthError has associated values, so give it the Equatable conformance
// the `catch ... where error == .userCancelled` clause above relies on.
extension FigmaOAuthError: Equatable {
    static func == (lhs: FigmaOAuthError, rhs: FigmaOAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.missingConfiguration, .missingConfiguration),
             (.userCancelled, .userCancelled),
             (.accessDenied, .accessDenied),
             (.stateMismatch, .stateMismatch),
             (.invalidCallback, .invalidCallback),
             (.notConnected, .notConnected):
            return true
        case let (.tokenExchangeFailed(l), .tokenExchangeFailed(r)):
            return l == r
        default:
            return false
        }
    }
}

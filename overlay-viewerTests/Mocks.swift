import AppKit
import Foundation
@testable import overlay_viewer

/// A fully in-memory `DesignSourceProviding` for exercising view models without
/// any real OAuth, network, or Safari involvement. Every outcome is scripted.
final class MockDesignSource: DesignSourceProviding {
    let displayName = "Mock"

    var isConfigured = true
    var isConnected = false
    var hasPersistedImage = false

    /// URLs this mock claims to handle. Defaults to anything with host "figma".
    var handledURLs: (URL) -> Bool = { $0.host?.contains("figma") ?? false }

    var connectResult: Result<String, Error> = .success("mock-user")
    var fetchResult: Result<NSImage, Error> = .success(NSImage())
    var restoreResult: Result<NSImage?, Error> = .success(nil)

    private(set) var connectCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var clearLastImageCallCount = 0
    private(set) var fetchedURLs: [URL] = []

    func canHandle(url: URL) -> Bool { handledURLs(url) }

    func connect() async throws -> String {
        connectCallCount += 1
        let handle = try connectResult.get()
        isConnected = true
        return handle
    }

    func disconnect() {
        disconnectCallCount += 1
        isConnected = false
    }

    func fetchImage(from url: URL) async throws -> NSImage {
        fetchedURLs.append(url)
        return try fetchResult.get()
    }

    func restoreLastImage() async throws -> NSImage? {
        try restoreResult.get()
    }

    func clearLastImage() {
        clearLastImageCallCount += 1
    }
}

/// Records every request it's given and replays queued responses in order,
/// so tests can assert on outgoing requests without hitting api.figma.com.
final class MockFigmaHTTPClient: FigmaHTTPClient {
    private(set) var requests: [URLRequest] = []
    var responses: [(Data, URLResponse)] = []
    var error: Error?

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let error { throw error }
        guard !responses.isEmpty else {
            throw URLError(.unknown)
        }
        return responses.removeFirst()
    }

    static func httpResponse(url: URL = URL(string: "https://api.figma.com/")!, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}

final class InMemoryTokenStore: FigmaTokenStoring {
    var tokens: FigmaTokens?

    init(tokens: FigmaTokens? = nil) {
        self.tokens = tokens
    }

    func save(_ tokens: FigmaTokens) { self.tokens = tokens }
    func load() -> FigmaTokens? { tokens }
    func clear() { tokens = nil }
}

enum TestFixtures {
    static let configuration = FigmaOAuthConfiguration(
        clientID: "test-client-id",
        clientSecret: "test-client-secret",
        redirectURI: "overlay-viewer://oauth-callback"
    )

    static func validTokens(expiresIn seconds: TimeInterval = 3600) -> FigmaTokens {
        FigmaTokens(accessToken: "valid-access-token", refreshToken: "valid-refresh-token", expiresAt: Date().addingTimeInterval(seconds))
    }

    static func expiredTokens() -> FigmaTokens {
        FigmaTokens(accessToken: "expired-access-token", refreshToken: "expired-refresh-token", expiresAt: Date().addingTimeInterval(-3600))
    }
}

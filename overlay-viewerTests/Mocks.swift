import Foundation
@testable import overlay_viewer

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

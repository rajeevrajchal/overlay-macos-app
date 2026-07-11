import XCTest
@testable import overlay_viewer

final class FigmaProviderTests: XCTestCase {

    private static let fileKeyDefaultsKey = "overlay.lastFigmaFileKey"
    private static let nodeIDDefaultsKey = "overlay.lastFigmaNodeID"

    private var originalFileKey: String?
    private var originalNodeID: String?

    override func setUp() {
        super.setUp()
        // Preserve whatever "last opened" state already exists on this
        // machine so the suite doesn't clobber a developer's real session.
        originalFileKey = UserDefaults.standard.string(forKey: Self.fileKeyDefaultsKey)
        originalNodeID = UserDefaults.standard.string(forKey: Self.nodeIDDefaultsKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        if let originalFileKey { defaults.set(originalFileKey, forKey: Self.fileKeyDefaultsKey) }
        else { defaults.removeObject(forKey: Self.fileKeyDefaultsKey) }
        if let originalNodeID { defaults.set(originalNodeID, forKey: Self.nodeIDDefaultsKey) }
        else { defaults.removeObject(forKey: Self.nodeIDDefaultsKey) }
        super.tearDown()
    }

    private func makeProvider(
        httpClient: MockFigmaHTTPClient = MockFigmaHTTPClient(),
        tokenStore: InMemoryTokenStore = InMemoryTokenStore(tokens: TestFixtures.validTokens())
    ) -> FigmaProvider {
        let oauth = FigmaOAuthService(configuration: TestFixtures.configuration, httpClient: httpClient, tokenStore: tokenStore)
        let apiClient = FigmaAPIClient(oauth: oauth, httpClient: httpClient)
        return FigmaProvider(oauth: oauth, apiClient: apiClient)
    }

    // MARK: - canHandle / isConfigured / isConnected

    func test_canHandle_delegatesToFigmaURLParser() {
        let provider = makeProvider()
        XCTAssertTrue(provider.canHandle(url: URL(string: "https://www.figma.com/file/abc123/Title")!))
        XCTAssertFalse(provider.canHandle(url: URL(string: "https://example.com/file/abc123/Title")!))
    }

    func test_isConnected_reflectsTokenStore() {
        let connected = makeProvider(tokenStore: InMemoryTokenStore(tokens: TestFixtures.validTokens()))
        let disconnected = makeProvider(tokenStore: InMemoryTokenStore(tokens: nil))
        XCTAssertTrue(connected.isConnected)
        XCTAssertFalse(disconnected.isConnected)
    }

    // MARK: - fetchImage

    func test_fetchImage_withValidFigmaURL_fetchesAndPersistsResource() async throws {
        let http = MockFigmaHTTPClient()
        http.responses = [(
            """
            {"images":{"1:2":"https://example.com/render.png"}}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        ), (
            makeTinyPNGData(),
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let provider = makeProvider(httpClient: http)

        _ = try await provider.fetchImage(from: URL(string: "https://www.figma.com/file/abc123/Title?node-id=1-2")!)

        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.fileKeyDefaultsKey), "abc123")
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.nodeIDDefaultsKey), "1:2")
    }

    func test_fetchImage_withNonFigmaURL_throwsUnsupportedURL() async {
        let provider = makeProvider()
        do {
            _ = try await provider.fetchImage(from: URL(string: "https://example.com/not-figma")!)
            XCTFail("expected unsupportedURL")
        } catch DesignSourceError.unsupportedURL {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - hasPersistedImage / restoreLastImage / clearLastImage

    func test_hasPersistedImage_falseWhenNotConnected() {
        UserDefaults.standard.set("abc123", forKey: Self.fileKeyDefaultsKey)
        let provider = makeProvider(tokenStore: InMemoryTokenStore(tokens: nil))
        XCTAssertFalse(provider.hasPersistedImage)
    }

    func test_hasPersistedImage_falseWhenConnectedButNothingPersisted() {
        UserDefaults.standard.removeObject(forKey: Self.fileKeyDefaultsKey)
        let provider = makeProvider(tokenStore: InMemoryTokenStore(tokens: TestFixtures.validTokens()))
        XCTAssertFalse(provider.hasPersistedImage)
    }

    func test_hasPersistedImage_trueWhenConnectedAndPersisted() {
        UserDefaults.standard.set("abc123", forKey: Self.fileKeyDefaultsKey)
        let provider = makeProvider(tokenStore: InMemoryTokenStore(tokens: TestFixtures.validTokens()))
        XCTAssertTrue(provider.hasPersistedImage)
    }

    func test_restoreLastImage_withNothingPersisted_returnsNil() async throws {
        UserDefaults.standard.removeObject(forKey: Self.fileKeyDefaultsKey)
        let provider = makeProvider()
        let image = try await provider.restoreLastImage()
        XCTAssertNil(image)
    }

    func test_restoreLastImage_withPersistedResource_fetchesImage() async throws {
        UserDefaults.standard.set("abc123", forKey: Self.fileKeyDefaultsKey)
        UserDefaults.standard.set("1:2", forKey: Self.nodeIDDefaultsKey)
        let http = MockFigmaHTTPClient()
        http.responses = [(
            """
            {"images":{"1:2":"https://example.com/render.png"}}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        ), (
            makeTinyPNGData(),
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let provider = makeProvider(httpClient: http)

        let image = try await provider.restoreLastImage()

        XCTAssertNotNil(image)
    }

    func test_clearLastImage_removesPersistedKeys() {
        UserDefaults.standard.set("abc123", forKey: Self.fileKeyDefaultsKey)
        UserDefaults.standard.set("1:2", forKey: Self.nodeIDDefaultsKey)
        let provider = makeProvider()

        provider.clearLastImage()

        XCTAssertNil(UserDefaults.standard.string(forKey: Self.fileKeyDefaultsKey))
        XCTAssertNil(UserDefaults.standard.string(forKey: Self.nodeIDDefaultsKey))
    }

    // MARK: - disconnect

    func test_disconnect_clearsTokenStore() {
        let tokenStore = InMemoryTokenStore(tokens: TestFixtures.validTokens())
        let provider = makeProvider(tokenStore: tokenStore)

        provider.disconnect()

        XCTAssertNil(tokenStore.tokens)
    }
}

/// A minimal valid 1x1 PNG, just enough for NSImage(data:) to decode successfully.
private func makeTinyPNGData() -> Data {
    let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    return Data(base64Encoded: base64)!
}

import XCTest
@testable import overlay_viewer

final class FigmaAPIClientTests: XCTestCase {

    private func makeClient(
        resourceHTTP: MockFigmaHTTPClient,
        oauthHTTP: MockFigmaHTTPClient = MockFigmaHTTPClient(),
        tokenStore: InMemoryTokenStore = InMemoryTokenStore(tokens: TestFixtures.validTokens())
    ) -> FigmaAPIClient {
        let oauth = FigmaOAuthService(configuration: TestFixtures.configuration, httpClient: oauthHTTP, tokenStore: tokenStore)
        return FigmaAPIClient(oauth: oauth, httpClient: resourceHTTP)
    }

    // MARK: - fetchProfile

    func test_fetchProfile_onSuccess_decodesProfile() async throws {
        let http = MockFigmaHTTPClient()
        http.responses = [(
            """
            {"handle":"jane","email":"jane@example.com"}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let client = makeClient(resourceHTTP: http)

        let profile = try await client.fetchProfile()

        XCTAssertEqual(profile.handle, "jane")
        XCTAssertEqual(profile.email, "jane@example.com")
        XCTAssertEqual(http.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer valid-access-token")
    }

    func test_fetchProfile_on403_throwsAccessDenied() async {
        let http = MockFigmaHTTPClient()
        http.responses = [(Data(), MockFigmaHTTPClient.httpResponse(statusCode: 403))]
        let client = makeClient(resourceHTTP: http)

        do {
            _ = try await client.fetchProfile()
            XCTFail("expected accessDenied")
        } catch FigmaAPIError.accessDenied {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchProfile_on401_refreshesTokenAndRetries() async throws {
        let resourceHTTP = MockFigmaHTTPClient()
        resourceHTTP.responses = [
            (Data(), MockFigmaHTTPClient.httpResponse(statusCode: 401)),
            ("""
            {"handle":"jane","email":null}
            """.data(using: .utf8)!, MockFigmaHTTPClient.httpResponse(statusCode: 200)),
        ]
        let oauthHTTP = MockFigmaHTTPClient()
        oauthHTTP.responses = [(
            """
            {"access_token":"refreshed","refresh_token":"refreshed-r","expires_in":3600}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let tokenStore = InMemoryTokenStore(tokens: TestFixtures.validTokens())
        let client = makeClient(resourceHTTP: resourceHTTP, oauthHTTP: oauthHTTP, tokenStore: tokenStore)

        let profile = try await client.fetchProfile()

        XCTAssertEqual(profile.handle, "jane")
        XCTAssertEqual(resourceHTTP.requests.count, 2)
        XCTAssertEqual(resourceHTTP.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
        XCTAssertEqual(tokenStore.tokens?.accessToken, "refreshed")
    }

    // MARK: - fetchRenderedImage: fileKey safety (regression for force-unwrap crash)

    func test_fetchRenderedImage_withFileKeyContainingUnsafeCharacters_doesNotCrashAndPercentEncodes() async throws {
        // Defense in depth: even though FigmaURLParser now rejects non-alphanumeric
        // fileKeys, FigmaAPIClient must not force-unwrap URLs built from caller input.
        let http = MockFigmaHTTPClient()
        http.responses = [(
            """
            {"images":{"1:2":"https://example.com/render.png"}}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let client = makeClient(resourceHTTP: http)

        do {
            _ = try await client.fetchRenderedImage(fileKey: "abc def#g?h", nodeID: "1:2")
        } catch {
            // Reaching the image-decode step is fine; "data isn't a real
            // image" is expected to fail. What matters is we got there
            // without crashing on a force-unwrap.
        }

        let sentRequest = try XCTUnwrap(http.requests.first)
        let urlString = try XCTUnwrap(sentRequest.url?.absoluteString)
        XCTAssertFalse(urlString.contains(" "), "fileKey must be percent-encoded before reaching the URL")
        XCTAssertTrue(urlString.hasPrefix("https://api.figma.com/v1/images/abc%20def"))
    }

    func test_fetchRenderedImage_withoutNodeID_usesFilesEndpointWithDepthQuery() async throws {
        let http = MockFigmaHTTPClient()
        http.responses = [(
            """
            {"thumbnailUrl":"https://example.com/thumb.png"}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        ), (
            Data(),
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let client = makeClient(resourceHTTP: http)

        _ = try? await client.fetchRenderedImage(fileKey: "abc123", nodeID: nil)

        let firstRequest = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(firstRequest.url?.absoluteString, "https://api.figma.com/v1/files/abc123?depth=1")
    }

    func test_fetchRenderedImage_withOversizedPayload_throwsInvalidResponse() async {
        let http = MockFigmaHTTPClient()
        let oversized = Data(count: 51 * 1024 * 1024)
        http.responses = [(
            """
            {"thumbnailUrl":"https://example.com/thumb.png"}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        ), (
            oversized,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let client = makeClient(resourceHTTP: http)

        do {
            _ = try await client.fetchRenderedImage(fileKey: "abc123", nodeID: nil)
            XCTFail("expected invalidResponse for oversized payload")
        } catch FigmaAPIError.invalidResponse {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_fetchRenderedImage_withNoImageInResponse_throwsNoImageReturned() async {
        let http = MockFigmaHTTPClient()
        http.responses = [(
            """
            {"images":{"1:2":null}}
            """.data(using: .utf8)!,
            MockFigmaHTTPClient.httpResponse(statusCode: 200)
        )]
        let client = makeClient(resourceHTTP: http)

        do {
            _ = try await client.fetchRenderedImage(fileKey: "abc123", nodeID: "1:2")
            XCTFail("expected noImageReturned")
        } catch FigmaAPIError.noImageReturned {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

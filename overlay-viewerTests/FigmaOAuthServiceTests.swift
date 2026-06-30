import XCTest
@testable import overlay_viewer

final class FigmaOAuthConfigurationTests: XCTestCase {

    func test_allVariablesPresent_buildsConfiguration() {
        let config = FigmaOAuthConfiguration.fromEnvironment([
            "FIGMA_CLIENT_ID": "id",
            "FIGMA_CLIENT_SECRET": "secret",
            "FIGMA_REDIRECT_URI": "scheme://callback",
        ])
        XCTAssertEqual(config?.clientID, "id")
        XCTAssertEqual(config?.clientSecret, "secret")
        XCTAssertEqual(config?.redirectURI, "scheme://callback")
    }

    func test_missingClientID_returnsNil() {
        let config = FigmaOAuthConfiguration.fromEnvironment([
            "FIGMA_CLIENT_SECRET": "secret",
            "FIGMA_REDIRECT_URI": "scheme://callback",
        ])
        XCTAssertNil(config)
    }

    func test_emptyClientSecret_returnsNil() {
        let config = FigmaOAuthConfiguration.fromEnvironment([
            "FIGMA_CLIENT_ID": "id",
            "FIGMA_CLIENT_SECRET": "",
            "FIGMA_REDIRECT_URI": "scheme://callback",
        ])
        XCTAssertNil(config)
    }

    func test_missingRedirectURI_returnsNil() {
        let config = FigmaOAuthConfiguration.fromEnvironment([
            "FIGMA_CLIENT_ID": "id",
            "FIGMA_CLIENT_SECRET": "secret",
        ])
        XCTAssertNil(config)
    }
}

final class FigmaOAuthServiceTests: XCTestCase {

    private func makeService(
        configuration: FigmaOAuthConfiguration? = TestFixtures.configuration,
        httpClient: MockFigmaHTTPClient = MockFigmaHTTPClient(),
        tokenStore: InMemoryTokenStore = InMemoryTokenStore()
    ) -> FigmaOAuthService {
        FigmaOAuthService(configuration: configuration, httpClient: httpClient, tokenStore: tokenStore)
    }

    // MARK: - buildAuthURL

    func test_buildAuthURL_includesAllRequiredParameters() throws {
        let service = makeService()
        let url = try service.buildAuthURL(state: "state-123", codeChallenge: "challenge-abc")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(byName["client_id"], "test-client-id")
        XCTAssertEqual(byName["redirect_uri"], "overlay-viewer://oauth-callback")
        XCTAssertEqual(byName["state"], "state-123")
        XCTAssertEqual(byName["code_challenge"], "challenge-abc")
        XCTAssertEqual(byName["code_challenge_method"], "S256")
        XCTAssertEqual(byName["response_type"], "code")
        XCTAssertEqual(byName["scope"], FigmaOAuthService.scopes.joined(separator: ","))
    }

    func test_buildAuthURL_withMissingConfiguration_throwsMissingConfiguration() {
        let service = makeService(configuration: nil)
        XCTAssertThrowsError(try service.buildAuthURL(state: "s", codeChallenge: "c")) { error in
            XCTAssertEqual(error as? FigmaOAuthError, .missingConfiguration)
        }
    }

    // MARK: - exchangeCodeForToken

    func test_exchangeCodeForToken_onSuccess_decodesTokenResponse() async throws {
        let http = MockFigmaHTTPClient()
        let responseJSON = """
        {"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}
        """.data(using: .utf8)!
        http.responses = [(responseJSON, MockFigmaHTTPClient.httpResponse(statusCode: 200))]
        let service = makeService(httpClient: http)

        let response = try await service.exchangeCodeForToken(code: "auth-code", codeVerifier: "verifier")

        XCTAssertEqual(response.access_token, "new-access")
        XCTAssertEqual(response.refresh_token, "new-refresh")
        XCTAssertEqual(response.expires_in, 3600)

        let sentRequest = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(sentRequest.url?.absoluteString, "https://api.figma.com/v1/oauth/token")
        XCTAssertEqual(sentRequest.httpMethod, "POST")
        XCTAssertNotNil(sentRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func test_exchangeCodeForToken_onNon2xxStatus_throwsTokenExchangeFailed() async {
        let http = MockFigmaHTTPClient()
        http.responses = [(Data(), MockFigmaHTTPClient.httpResponse(statusCode: 400))]
        let service = makeService(httpClient: http)

        do {
            _ = try await service.exchangeCodeForToken(code: "bad-code", codeVerifier: "verifier")
            XCTFail("expected tokenExchangeFailed")
        } catch FigmaOAuthError.tokenExchangeFailed(let code) {
            XCTAssertEqual(code, 400)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_exchangeCodeForToken_withMissingConfiguration_throwsMissingConfiguration() async {
        let service = makeService(configuration: nil)
        do {
            _ = try await service.exchangeCodeForToken(code: "code", codeVerifier: "verifier")
            XCTFail("expected missingConfiguration")
        } catch {
            XCTAssertEqual(error as? FigmaOAuthError, .missingConfiguration)
        }
    }

    // MARK: - validAccessToken / forceRefresh

    func test_validAccessToken_withUnexpiredToken_returnsCachedTokenWithoutNetworkCall() async throws {
        let http = MockFigmaHTTPClient()
        let tokenStore = InMemoryTokenStore(tokens: TestFixtures.validTokens())
        let service = makeService(httpClient: http, tokenStore: tokenStore)

        let token = try await service.validAccessToken()

        XCTAssertEqual(token, "valid-access-token")
        XCTAssertTrue(http.requests.isEmpty, "should not hit the network for a non-expired token")
    }

    func test_validAccessToken_withNoStoredToken_throwsNotConnected() async {
        let service = makeService(tokenStore: InMemoryTokenStore(tokens: nil))
        do {
            _ = try await service.validAccessToken()
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? FigmaOAuthError, .notConnected)
        }
    }

    func test_validAccessToken_withExpiredToken_refreshesAndPersistsNewToken() async throws {
        let http = MockFigmaHTTPClient()
        let refreshJSON = """
        {"access_token":"refreshed-access","refresh_token":"refreshed-refresh","expires_in":7200}
        """.data(using: .utf8)!
        http.responses = [(refreshJSON, MockFigmaHTTPClient.httpResponse(statusCode: 200))]
        let tokenStore = InMemoryTokenStore(tokens: TestFixtures.expiredTokens())
        let service = makeService(httpClient: http, tokenStore: tokenStore)

        let token = try await service.validAccessToken()

        XCTAssertEqual(token, "refreshed-access")
        XCTAssertEqual(tokenStore.tokens?.accessToken, "refreshed-access")
        XCTAssertEqual(http.requests.first?.url?.absoluteString, "https://api.figma.com/v1/oauth/refresh")
    }

    func test_forceRefresh_withNoStoredToken_throwsNotConnected() async {
        let service = makeService(tokenStore: InMemoryTokenStore(tokens: nil))
        do {
            _ = try await service.forceRefresh()
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? FigmaOAuthError, .notConnected)
        }
    }

    // MARK: - disconnect / isConnected

    func test_disconnect_clearsTokenStore() {
        let tokenStore = InMemoryTokenStore(tokens: TestFixtures.validTokens())
        let service = makeService(tokenStore: tokenStore)

        service.disconnect()

        XCTAssertNil(tokenStore.tokens)
    }

    func test_isConnected_reflectsTokenStorePresence() {
        let connected = makeService(tokenStore: InMemoryTokenStore(tokens: TestFixtures.validTokens()))
        let disconnected = makeService(tokenStore: InMemoryTokenStore(tokens: nil))

        XCTAssertTrue(connected.isConnected)
        XCTAssertFalse(disconnected.isConnected)
    }
}

extension FigmaOAuthError: Equatable {
    public static func == (lhs: FigmaOAuthError, rhs: FigmaOAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.missingConfiguration, .missingConfiguration),
             (.userCancelled, .userCancelled),
             (.accessDenied, .accessDenied),
             (.stateMismatch, .stateMismatch),
             (.invalidCallback, .invalidCallback),
             (.notConnected, .notConnected):
            return true
        case (.tokenExchangeFailed(let l), .tokenExchangeFailed(let r)):
            return l == r
        default:
            return false
        }
    }
}

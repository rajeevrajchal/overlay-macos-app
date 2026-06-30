import Foundation
import AuthenticationServices
import CryptoKit
import Cocoa

/// Minimal abstraction over the network call FigmaOAuthService needs,
/// so tests can inject a mock instead of hitting api.figma.com.
protocol FigmaHTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: FigmaHTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

struct FigmaOAuthConfiguration {
    let clientID: String
    let clientSecret: String
    let redirectURI: String

    /// Figma desktop/native apps still require a client_secret on every token
    /// exchange (PKCE is additive there, not a substitute — see README). With
    /// no backend to hold it, these are read from the process environment,
    /// which you set via the Xcode scheme's "Arguments > Environment Variables"
    /// for local runs. See README for FIGMA_CLIENT_ID / FIGMA_CLIENT_SECRET /
    /// FIGMA_REDIRECT_URI.
    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> FigmaOAuthConfiguration? {
        guard let id = environment["FIGMA_CLIENT_ID"], !id.isEmpty,
              let secret = environment["FIGMA_CLIENT_SECRET"], !secret.isEmpty,
              let redirect = environment["FIGMA_REDIRECT_URI"], !redirect.isEmpty
        else { return nil }
        return FigmaOAuthConfiguration(clientID: id, clientSecret: secret, redirectURI: redirect)
    }
}

struct FigmaTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

struct FigmaProfile: Codable {
    let handle: String
    let email: String?
}

enum FigmaOAuthError: Error, LocalizedError {
    case missingConfiguration
    case userCancelled
    case accessDenied
    case stateMismatch
    case invalidCallback
    case tokenExchangeFailed(Int)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Figma isn't configured. Set FIGMA_CLIENT_ID, FIGMA_CLIENT_SECRET, and FIGMA_REDIRECT_URI."
        case .userCancelled:
            return "Figma connection was cancelled."
        case .accessDenied:
            return "Figma access was denied."
        case .stateMismatch:
            return "Security check failed — please try connecting again."
        case .invalidCallback:
            return "Figma sent back an unexpected response."
        case .tokenExchangeFailed(let code):
            return "Couldn't complete the Figma sign-in (\(code))."
        case .notConnected:
            return "Figma isn't connected."
        }
    }
}

/// Owns the entire Figma OAuth2 lifecycle: building the consent URL, running
/// the system-browser auth session, exchanging/refreshing tokens, and
/// persisting them. Nothing outside this type should talk to
/// api.figma.com/v1/oauth/* or touch the Keychain entry it owns.
final class FigmaOAuthService: NSObject {

    static let shared = FigmaOAuthService()

    static let scopes = ["file_content:read", "current_user:read"]

    private let configuration: FigmaOAuthConfiguration?
    private let httpClient: FigmaHTTPClient
    private let tokenStore: FigmaTokenStoring

    /// Stand-in for "store state server-side keyed to the session": this app
    /// has exactly one session (itself), so an in-memory property is that store.
    private var pendingState: String?

    init(configuration: FigmaOAuthConfiguration? = .fromEnvironment(),
         httpClient: FigmaHTTPClient = URLSession.shared,
         tokenStore: FigmaTokenStoring = FigmaKeychainTokenStore()) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.tokenStore = tokenStore
    }

    var isConnected: Bool { tokenStore.load() != nil }

    // MARK: - PKCE / state

    func generateState() -> String { Self.randomURLSafeString(byteCount: 32) }

    private func generateCodeVerifier() -> String { Self.randomURLSafeString(byteCount: 48) }

    private func codeChallenge(forVerifier verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Self.base64URLEncode(Data(digest))
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URLEncode(Data(bytes))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Authorize URL

    func buildAuthURL(state: String, codeChallenge: String, scopes: [String] = FigmaOAuthService.scopes) throws -> URL {
        guard let configuration else { throw FigmaOAuthError.missingConfiguration }
        var components = URLComponents(string: "https://www.figma.com/oauth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw FigmaOAuthError.invalidCallback }
        return url
    }

    // MARK: - Token exchange / refresh

    func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> FigmaTokenResponse {
        guard let configuration else { throw FigmaOAuthError.missingConfiguration }
        var request = URLRequest(url: URL(string: "https://api.figma.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.basicAuthHeader(configuration), forHTTPHeaderField: "Authorization")
        request.httpBody = Self.formEncode([
            "redirect_uri": configuration.redirectURI,
            "code": code,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier,
        ])
        return try await send(request)
    }

    func refreshToken(_ refreshToken: String) async throws -> FigmaTokenResponse {
        guard let configuration else { throw FigmaOAuthError.missingConfiguration }
        var request = URLRequest(url: URL(string: "https://api.figma.com/v1/oauth/refresh")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.basicAuthHeader(configuration), forHTTPHeaderField: "Authorization")
        request.httpBody = Self.formEncode(["refresh_token": refreshToken])
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> FigmaTokenResponse {
        let (data, response) = try await httpClient.send(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw FigmaOAuthError.tokenExchangeFailed(code)
        }
        do {
            return try JSONDecoder().decode(FigmaTokenResponse.self, from: data)
        } catch {
            throw FigmaOAuthError.tokenExchangeFailed(http.statusCode)
        }
    }

    private static func basicAuthHeader(_ configuration: FigmaOAuthConfiguration) -> String {
        let raw = "\(configuration.clientID):\(configuration.clientSecret)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        params.map { key, value in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")
        .data(using: .utf8)!
    }

    // MARK: - Access token retrieval (transparent refresh)

    /// Returns a presumed-valid access token, refreshing first if the cached
    /// one is at/near expiry. Throws `.notConnected` if there's nothing stored.
    func validAccessToken() async throws -> String {
        guard let tokens = tokenStore.load() else { throw FigmaOAuthError.notConnected }
        guard tokens.isExpired else { return tokens.accessToken }
        return try await forceRefresh()
    }

    /// Always hits the refresh endpoint. Callers use this after a 401 from
    /// the Figma API even if the cached token looked unexpired.
    @discardableResult
    func forceRefresh() async throws -> String {
        guard let tokens = tokenStore.load() else { throw FigmaOAuthError.notConnected }
        let response = try await refreshToken(tokens.refreshToken)
        let newTokens = FigmaTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in))
        )
        tokenStore.save(newTokens)
        return newTokens.accessToken
    }

    // MARK: - Disconnect

    func disconnect() {
        tokenStore.clear()
    }

    // MARK: - Full interactive flow

    /// Opens Figma's consent screen in a system-mediated browser context
    /// (never this app's own webview — Figma blocks those), validates the
    /// CSRF state, exchanges the code, persists tokens, and returns the
    /// connected user's profile.
    @MainActor
    func authenticate() async throws -> FigmaProfile {
        guard configuration != nil else { throw FigmaOAuthError.missingConfiguration }

        let state = generateState()
        let verifier = generateCodeVerifier()
        let challenge = codeChallenge(forVerifier: verifier)
        let authURL = try buildAuthURL(state: state, codeChallenge: challenge)
        guard let callbackScheme = URL(string: configuration!.redirectURI)?.scheme else {
            throw FigmaOAuthError.missingConfiguration
        }
        pendingState = state

        let callbackURL = try await runWebAuthSession(authURL: authURL, callbackScheme: callbackScheme)
        let code = try validateCallback(callbackURL, expectedState: state)
        pendingState = nil

        let tokenResponse = try await exchangeCodeForToken(code: code, codeVerifier: verifier)
        let tokens = FigmaTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
        )
        tokenStore.save(tokens)

        return try await FigmaAPIClient.shared.fetchProfile()
    }

    @MainActor
    private func runWebAuthSession(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: FigmaOAuthError.userCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: FigmaOAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            session.start()
        }
    }

    private var activeSession: ASWebAuthenticationSession?

    private func validateCallback(_ url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let errorParam = items.first(where: { $0.name == "error" })?.value {
            throw errorParam == "access_denied" ? FigmaOAuthError.accessDenied : FigmaOAuthError.invalidCallback
        }
        guard let returnedState = items.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState else {
            throw FigmaOAuthError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw FigmaOAuthError.invalidCallback
        }
        return code
    }
}

extension FigmaOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

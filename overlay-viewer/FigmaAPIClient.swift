import Cocoa

enum FigmaAPIError: Error, LocalizedError {
    case accessDenied
    case invalidResponse
    case requestFailed(Int)
    case noImageReturned

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "You don't have access to that Figma file with the connected account."
        case .invalidResponse:
            return "Figma returned an unexpected response."
        case .requestFailed(let code):
            return "Figma request failed (\(code))."
        case .noImageReturned:
            return "Figma didn't return an image for that file."
        }
    }
}

/// All authenticated calls to api.figma.com go through here. Resource
/// fetching depends on FigmaOAuthService for tokens — it never duplicates
/// auth logic (token storage, refresh) itself.
final class FigmaAPIClient {

    static let shared = FigmaAPIClient()

    private let oauth: FigmaOAuthService
    private let httpClient: FigmaHTTPClient

    init(oauth: FigmaOAuthService = .shared, httpClient: FigmaHTTPClient = URLSession.shared) {
        self.oauth = oauth
        self.httpClient = httpClient
    }

    // MARK: - Profile

    func fetchProfile() async throws -> FigmaProfile {
        let data = try await authorizedRequest { token in
            var request = URLRequest(url: URL(string: "https://api.figma.com/v1/me")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        guard let profile = try? JSONDecoder().decode(FigmaProfile.self, from: data) else {
            throw FigmaAPIError.invalidResponse
        }
        return profile
    }

    // MARK: - Rendered image

    /// Fetches a static render of the given file/node and decodes it as an
    /// NSImage, suitable for dropping straight into ImageCanvasView. This
    /// replaces the old WKWebView embed for any OAuth-authenticated file —
    /// the embed iframe has no way to accept a bearer token, so it could
    /// never see private files; a real rendered image fetched with the
    /// token can.
    func fetchRenderedImage(fileKey: String, nodeID: String?) async throws -> NSImage {
        let imageURLString = try await fetchImageURLString(fileKey: fileKey, nodeID: nodeID)
        guard let imageURL = URL(string: imageURLString) else { throw FigmaAPIError.invalidResponse }
        let (data, response) = try await httpClient.send(URLRequest(url: imageURL))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FigmaAPIError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let image = NSImage(data: data) else { throw FigmaAPIError.invalidResponse }
        return image
    }

    private func fetchImageURLString(fileKey: String, nodeID: String?) async throws -> String {
        if let nodeID {
            let data = try await authorizedRequest { token in
                var components = URLComponents(string: "https://api.figma.com/v1/images/\(fileKey)")!
                components.queryItems = [
                    URLQueryItem(name: "ids", value: nodeID),
                    URLQueryItem(name: "format", value: "png"),
                    URLQueryItem(name: "scale", value: "2"),
                ]
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }
            struct ImagesResponse: Decodable { let images: [String: String?] }
            guard let decoded = try? JSONDecoder().decode(ImagesResponse.self, from: data),
                  let urlString = decoded.images[nodeID] ?? nil else {
                throw FigmaAPIError.noImageReturned
            }
            return urlString
        } else {
            let data = try await authorizedRequest { token in
                var request = URLRequest(url: URL(string: "https://api.figma.com/v1/files/\(fileKey)?depth=1")!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }
            struct FileResponse: Decodable { let thumbnailUrl: String? }
            guard let decoded = try? JSONDecoder().decode(FileResponse.self, from: data),
                  let urlString = decoded.thumbnailUrl else {
                throw FigmaAPIError.noImageReturned
            }
            return urlString
        }
    }

    // MARK: - Authorized request with one transparent refresh-and-retry

    private func authorizedRequest(_ build: @escaping (String) -> URLRequest) async throws -> Data {
        let token = try await oauth.validAccessToken()
        let (data, response) = try await httpClient.send(build(token))
        guard let http = response as? HTTPURLResponse else { throw FigmaAPIError.invalidResponse }

        if http.statusCode == 401 {
            let refreshedToken = try await oauth.forceRefresh()
            let (retryData, retryResponse) = try await httpClient.send(build(refreshedToken))
            return try Self.validate(retryData, retryResponse)
        }

        return try Self.validate(data, response)
    }

    private static func validate(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw FigmaAPIError.invalidResponse }
        if http.statusCode == 403 || http.statusCode == 404 { throw FigmaAPIError.accessDenied }
        guard (200..<300).contains(http.statusCode) else { throw FigmaAPIError.requestFailed(http.statusCode) }
        return data
    }
}

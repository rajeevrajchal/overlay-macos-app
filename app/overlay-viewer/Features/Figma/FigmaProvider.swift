import Cocoa

/// Adapts the Figma-specific OAuth/API/URL-parsing trio to the generic
/// DesignSourceProviding seam, and owns the "last opened Figma resource"
/// persistence that used to live inline in OverlayWindowController — so the
/// window layer no longer needs to know Figma has a fileKey/nodeID at all.
final class FigmaProvider: DesignSourceProviding {

    let displayName = "Figma"

    private let oauth: FigmaOAuthService
    private let apiClient: FigmaAPIClient

    private static let lastFileKeyKey = "overlay.lastFigmaFileKey"
    private static let lastNodeIDKey  = "overlay.lastFigmaNodeID"

    init(oauth: FigmaOAuthService = .shared, apiClient: FigmaAPIClient = .shared) {
        self.oauth = oauth
        self.apiClient = apiClient
    }

    var isConfigured: Bool { oauth.isConfigured }
    var isConnected: Bool { oauth.isConnected }

    var hasPersistedImage: Bool {
        isConnected && UserDefaults.standard.string(forKey: Self.lastFileKeyKey) != nil
    }

    func canHandle(url: URL) -> Bool {
        FigmaURLParser.parse(url) != nil
    }

    func connect() async throws -> String {
        try await oauth.authenticate().handle
    }

    func disconnect() {
        oauth.disconnect()
    }

    func fetchImage(from url: URL) async throws -> NSImage {
        guard let resource = FigmaURLParser.parse(url) else {
            throw DesignSourceError.unsupportedURL
        }
        let image = try await apiClient.fetchRenderedImage(fileKey: resource.fileKey, nodeID: resource.nodeID)
        persist(resource)
        return image
    }

    func restoreLastImage() async throws -> NSImage? {
        guard isConnected, let fileKey = UserDefaults.standard.string(forKey: Self.lastFileKeyKey) else {
            return nil
        }
        let nodeID = UserDefaults.standard.string(forKey: Self.lastNodeIDKey)
        return try await apiClient.fetchRenderedImage(fileKey: fileKey, nodeID: nodeID)
    }

    func clearLastImage() {
        UserDefaults.standard.removeObject(forKey: Self.lastFileKeyKey)
        UserDefaults.standard.removeObject(forKey: Self.lastNodeIDKey)
    }

    private func persist(_ resource: FigmaURLParser.Resource) {
        UserDefaults.standard.set(resource.fileKey, forKey: Self.lastFileKeyKey)
        if let nodeID = resource.nodeID {
            UserDefaults.standard.set(nodeID, forKey: Self.lastNodeIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.lastNodeIDKey)
        }
    }
}

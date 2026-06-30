import Foundation

/// Parses a pasted Figma URL into the pieces the REST API needs. This is the
/// entire job of the URL field now — it's a resource locator, not something
/// that gets loaded directly; actual fetching goes through FigmaAPIClient.
enum FigmaURLParser {

    struct Resource: Equatable {
        let fileKey: String
        let nodeID: String?
    }

    static func parse(_ url: URL) -> Resource? {
        guard url.host?.hasSuffix("figma.com") == true else { return nil }

        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count >= 2, segments[0] == "file" || segments[0] == "design" else { return nil }
        let fileKey = segments[1]
        guard !fileKey.isEmpty else { return nil }

        let nodeID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "node-id" }?
            .value?
            .replacingOccurrences(of: "-", with: ":")

        return Resource(fileKey: fileKey, nodeID: nodeID)
    }
}

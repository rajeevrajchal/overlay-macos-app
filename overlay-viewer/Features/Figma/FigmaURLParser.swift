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
        guard let host = url.host,
              host == "figma.com" || host == "www.figma.com" || host.hasSuffix(".figma.com")
        else { return nil }

        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count >= 2, segments[0] == "file" || segments[0] == "design" else { return nil }
        let fileKey = segments[1]
        // Figma file keys are alphanumeric; rejecting anything else keeps
        // this value safe to interpolate into request URLs downstream.
        guard !fileKey.isEmpty, fileKey.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }

        let rawNodeID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "node-id" }?
            .value?
            .replacingOccurrences(of: "-", with: ":")
        let nodeID = rawNodeID.flatMap { id in
            id.allSatisfy { $0.isNumber || $0 == ":" } ? id : nil
        }

        return Resource(fileKey: fileKey, nodeID: nodeID)
    }
}

import XCTest
@testable import overlay_viewer

final class FigmaURLParserTests: XCTestCase {

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    // MARK: - Happy path

    func test_parsesFileURL_returnsFileKeyWithNoNodeID() {
        let resource = FigmaURLParser.parse(url("https://www.figma.com/file/abc123/My-Design"))
        XCTAssertEqual(resource, .init(fileKey: "abc123", nodeID: nil))
    }

    func test_parsesDesignURL_returnsFileKey() {
        let resource = FigmaURLParser.parse(url("https://www.figma.com/design/xyz789/My-Design"))
        XCTAssertEqual(resource, .init(fileKey: "xyz789", nodeID: nil))
    }

    func test_parsesNodeIDQueryParam_convertsDashToColon() {
        let resource = FigmaURLParser.parse(url("https://www.figma.com/file/abc123/Title?node-id=12-345"))
        XCTAssertEqual(resource, .init(fileKey: "abc123", nodeID: "12:345"))
    }

    func test_bareHostFigmaCom_isAccepted() {
        let resource = FigmaURLParser.parse(url("https://figma.com/file/abc123/Title"))
        XCTAssertEqual(resource?.fileKey, "abc123")
    }

    func test_subdomainOfFigmaCom_isAccepted() {
        let resource = FigmaURLParser.parse(url("https://branding.figma.com/file/abc123/Title"))
        XCTAssertEqual(resource?.fileKey, "abc123")
    }

    // MARK: - Edge / boundary

    func test_nodeIDWithMultipleDashes_convertsAllToColons() {
        let resource = FigmaURLParser.parse(url("https://www.figma.com/file/abc123/Title?node-id=1-2-3"))
        XCTAssertEqual(resource?.nodeID, "1:2:3")
    }

    func test_missingNodeIDQueryParam_returnsNilNodeID() {
        let resource = FigmaURLParser.parse(url("https://www.figma.com/file/abc123/Title?other=1"))
        XCTAssertNil(resource?.nodeID)
    }

    // MARK: - Invalid / malicious input

    func test_nonFigmaHost_returnsNil() {
        XCTAssertNil(FigmaURLParser.parse(url("https://example.com/file/abc123/Title")))
    }

    func test_hostSuffixSpoofing_isRejected() {
        // Regression: a naive `hasSuffix("figma.com")` check would accept this.
        XCTAssertNil(FigmaURLParser.parse(url("https://evilfigma.com/file/abc123/Title")))
        XCTAssertNil(FigmaURLParser.parse(url("https://notfigma.com.attacker.net/file/abc123/Title")))
    }

    func test_missingPathSegments_returnsNil() {
        XCTAssertNil(FigmaURLParser.parse(url("https://www.figma.com/file")))
        XCTAssertNil(FigmaURLParser.parse(url("https://www.figma.com/")))
    }

    func test_unrecognizedResourceType_returnsNil() {
        XCTAssertNil(FigmaURLParser.parse(url("https://www.figma.com/proto/abc123/Title")))
    }

    func test_fileKeyWithUnsafeCharacters_isRejected() {
        // Regression for the force-unwrap crash: a raw space/`#`/`?` in the
        // decoded path segment must not be accepted as a fileKey, since it
        // gets interpolated into request URLs downstream.
        XCTAssertNil(FigmaURLParser.parse(url("https://www.figma.com/file/abc%20def/Title")))
        XCTAssertNil(FigmaURLParser.parse(url("https://www.figma.com/file/abc%23def/Title")))
        XCTAssertNil(FigmaURLParser.parse(url("https://www.figma.com/file/abc%3Fdef/Title")))
    }

    func test_nodeIDWithUnsafeCharacters_isDroppedButFileKeyKept() {
        let resource = FigmaURLParser.parse(url("https://www.figma.com/file/abc123/Title?node-id=12%3Bdrop"))
        XCTAssertEqual(resource?.fileKey, "abc123")
        XCTAssertNil(resource?.nodeID)
    }
}

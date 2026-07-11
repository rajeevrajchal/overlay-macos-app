import XCTest
@testable import overlay_viewer

@MainActor
final class WelcomeViewModelTests: XCTestCase {

    private static let handleKey = "overlay.figmaHandle"
    private var originalHandle: String?

    override func setUp() {
        super.setUp()
        originalHandle = UserDefaults.standard.string(forKey: Self.handleKey)
        UserDefaults.standard.removeObject(forKey: Self.handleKey)
    }

    override func tearDown() {
        if let originalHandle { UserDefaults.standard.set(originalHandle, forKey: Self.handleKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.handleKey) }
        super.tearDown()
    }

    // MARK: Init / configuration

    func test_init_disconnected_whenSourceNotConnected() {
        let source = MockDesignSource()
        let vm = WelcomeViewModel(source: source)
        XCTAssertEqual(vm.connection, .disconnected)
    }

    func test_init_reflectsConfiguredFlag() {
        let source = MockDesignSource()
        source.isConfigured = false
        let vm = WelcomeViewModel(source: source)
        XCTAssertFalse(vm.isFigmaConfigured)
    }

    // MARK: Connect

    func test_connect_success_setsConnectedAndPersistsHandle() async {
        let source = MockDesignSource()
        source.connectResult = .success("ada")
        let vm = WelcomeViewModel(source: source)

        vm.connect()
        await waitUntil { vm.connection == .connected(workspace: "ada") }

        XCTAssertEqual(vm.connection, .connected(workspace: "ada"))
        XCTAssertEqual(source.connectCallCount, 1)
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.handleKey), "ada")
    }

    func test_connect_userCancelled_returnsToDisconnectedQuietly() async {
        let source = MockDesignSource()
        source.connectResult = .failure(FigmaOAuthError.userCancelled)
        let vm = WelcomeViewModel(source: source)

        vm.connect()
        await waitUntil { vm.connection == .disconnected }

        XCTAssertEqual(vm.connection, .disconnected)
        XCTAssertNil(vm.errorMessage)
    }

    func test_connect_failure_setsFailedState() async {
        let source = MockDesignSource()
        source.connectResult = .failure(FigmaOAuthError.tokenExchangeFailed(500))
        let vm = WelcomeViewModel(source: source)

        vm.connect()
        await waitUntil { if case .failed = vm.connection { return true } else { return false } }

        guard case .failed = vm.connection else {
            return XCTFail("expected failed state, got \(vm.connection)")
        }
    }

    func test_disconnect_clearsStateAndHandle() {
        let source = MockDesignSource()
        source.isConnected = true
        UserDefaults.standard.set("ada", forKey: Self.handleKey)
        let vm = WelcomeViewModel(source: source)

        vm.disconnect()

        XCTAssertEqual(vm.connection, .disconnected)
        XCTAssertEqual(source.disconnectCallCount, 1)
        XCTAssertNil(UserDefaults.standard.string(forKey: Self.handleKey))
    }

    // MARK: Open Figma URL

    func test_openFigmaURL_rejectsUnhandledURL() {
        let source = MockDesignSource()
        source.isConnected = true
        let vm = WelcomeViewModel(source: source)
        vm.figmaURLText = "https://example.com/not-figma"

        vm.openFigmaURL()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(source.fetchedURLs.isEmpty)
    }

    func test_openFigmaURL_requiresConnection() {
        let source = MockDesignSource()
        source.isConnected = false
        let vm = WelcomeViewModel(source: source)
        vm.figmaURLText = "https://figma.com/design/abc"

        vm.openFigmaURL()

        XCTAssertEqual(vm.errorMessage, "Connect Figma first, then paste the URL.")
        XCTAssertTrue(source.fetchedURLs.isEmpty)
    }

    func test_openFigmaURL_success_deliversImage() async {
        let source = MockDesignSource()
        source.isConnected = true
        let image = NSImage()
        source.fetchResult = .success(image)
        let vm = WelcomeViewModel(source: source)
        vm.figmaURLText = "https://figma.com/design/abc"

        var delivered: NSImage?
        vm.onProviderImageLoaded = { delivered = $0 }

        vm.openFigmaURL()
        await waitUntil { delivered != nil }

        XCTAssertTrue(delivered === image)
        XCTAssertEqual(source.fetchedURLs.count, 1)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: Helpers

    /// Spins the main run loop until `condition` holds or the timeout elapses —
    /// enough for the view model's internal `Task { … }` (which never really
    /// suspends against the mock) to complete.
    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

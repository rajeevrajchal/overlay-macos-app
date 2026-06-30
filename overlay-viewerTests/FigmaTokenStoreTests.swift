import XCTest
@testable import overlay_viewer

final class FigmaTokensExpiryTests: XCTestCase {

    func test_tokenFarInFuture_isNotExpired() {
        let tokens = FigmaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600))
        XCTAssertFalse(tokens.isExpired)
    }

    func test_tokenInThePast_isExpired() {
        let tokens = FigmaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(-10))
        XCTAssertTrue(tokens.isExpired)
    }

    func test_tokenWithinSkewWindow_isTreatedAsExpired() {
        // 60s skew: a token expiring in 30s should already be considered expired.
        let tokens = FigmaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(30))
        XCTAssertTrue(tokens.isExpired)
    }

    func test_tokenJustOutsideSkewWindow_isNotExpired() {
        let tokens = FigmaTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(120))
        XCTAssertFalse(tokens.isExpired)
    }
}

final class FigmaKeychainTokenStoreTests: XCTestCase {

    private let store = FigmaKeychainTokenStore()
    private var originalTokens: FigmaTokens?

    override func setUp() {
        super.setUp()
        // Preserve whatever the developer running these tests actually has
        // connected, so the suite doesn't silently log them out of Figma.
        originalTokens = store.load()
    }

    override func tearDown() {
        if let originalTokens {
            store.save(originalTokens)
        } else {
            store.clear()
        }
        super.tearDown()
    }

    func test_saveThenLoad_roundTripsTokens() {
        let tokens = FigmaTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date().addingTimeInterval(1000))
        store.save(tokens)

        let loaded = store.load()
        XCTAssertEqual(loaded?.accessToken, "access-1")
        XCTAssertEqual(loaded?.refreshToken, "refresh-1")
    }

    func test_save_overwritesPreviousValue() {
        store.save(FigmaTokens(accessToken: "first", refreshToken: "r1", expiresAt: Date()))
        store.save(FigmaTokens(accessToken: "second", refreshToken: "r2", expiresAt: Date()))

        XCTAssertEqual(store.load()?.accessToken, "second")
    }

    func test_clear_removesStoredTokens() {
        store.save(FigmaTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date()))
        store.clear()

        XCTAssertNil(store.load())
    }

    func test_load_withNothingStored_returnsNil() {
        store.clear()
        XCTAssertNil(store.load())
    }
}

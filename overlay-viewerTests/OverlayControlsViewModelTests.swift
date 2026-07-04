import XCTest
@testable import overlay_viewer

@MainActor
final class OverlayControlsViewModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "OverlayControlsViewModelTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaultOpacity_isFull_whenNothingStored() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        XCTAssertEqual(vm.opacity, 1.0)
        XCTAssertEqual(vm.opacityPercent, 100)
    }

    func test_init_readsStoredValue() {
        defaults.set(0.42, forKey: "overlay.opacity")
        let vm = OverlayControlsViewModel(defaults: defaults)
        XCTAssertEqual(vm.opacity, 0.42, accuracy: 0.0001)
        XCTAssertEqual(vm.opacityPercent, 42)
    }

    func test_nudge_increments() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        vm.opacity = 0.5
        vm.nudgeOpacity(by: 0.01)
        XCTAssertEqual(vm.opacity, 0.51, accuracy: 0.0001)
    }

    func test_nudge_clampsAtUpperBound() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        vm.opacity = 1.0
        vm.nudgeOpacity(by: 0.05)
        XCTAssertEqual(vm.opacity, 1.0)
    }

    func test_nudge_clampsAtLowerBound() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        vm.opacity = 0.1
        vm.nudgeOpacity(by: -0.5)
        XCTAssertEqual(vm.opacity, 0.1)
    }

    func test_accessibilityValue_readsAsPercent() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        vm.opacity = 0.62
        XCTAssertEqual(vm.accessibilityOpacityValue, "62 percent")
    }

    func test_persist_writesCurrentValue() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        vm.opacity = 0.33
        vm.persist()
        XCTAssertEqual(defaults.double(forKey: "overlay.opacity"), 0.33, accuracy: 0.0001)
    }

    func test_intents_invokeClosures() {
        let vm = OverlayControlsViewModel(defaults: defaults)
        var closed = false
        var removed = false
        vm.onClose = { closed = true }
        vm.onRemove = { removed = true }
        vm.requestClose()
        vm.requestRemove()
        XCTAssertTrue(closed)
        XCTAssertTrue(removed)
    }
}

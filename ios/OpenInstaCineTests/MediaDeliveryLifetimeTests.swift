import XCTest

@testable import OpenInstaCine

@MainActor
final class MediaDeliveryLifetimeTests: XCTestCase {
    func testFrameioPreflightRejectionRestoresTransferredHop() async {
        let model = AppModel()
        // Simulate the popup's already-completed handoff without leaving any
        // Wi-Fi network. The fixture has no camera or credentials to rejoin.
        let token = model.internetHop.begin()
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .frameio, configuration: .init(), internetHopToken: token)

        let outcome = await MediaDeliveryRunner.execute(request: request, model: model) { _ in
            XCTFail("An empty request must fail before presenting progress")
        }

        guard case .failed = outcome else {
            return XCTFail("An empty request must fail preflight")
        }
        XCTAssertFalse(
            model.internetHopActive, "Preflight failure must release the transferred hop")
    }

    func testNativePreflightDoesNotAdoptUnrelatedInternetHop() async {
        let model = AppModel()
        let token = model.internetHop.begin()
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .nativeShare, configuration: .init())

        _ = await MediaDeliveryRunner.execute(request: request, model: model) { _ in }

        XCTAssertTrue(model.internetHopActive, "Native export never owns an internet hop")
        model.endInternetHop(token)
    }

    func testTransferredPopupCloseCannotReleaseAcceptedDelivery() async {
        let model = AppModel()
        let popup = model.internetHop.begin()
        let delivery = model.transferInternetHop(popup)
        XCTAssertNotNil(delivery)
        model.endInternetHop(popup)
        XCTAssertTrue(model.internetHopActive)
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .frameio, configuration: .init(),
            internetHopToken: delivery)
        _ = await MediaDeliveryRunner.execute(request: request, model: model) { _ in
            XCTFail("An empty request must fail before presenting progress")
        }
        XCTAssertFalse(model.internetHopActive)
    }

    func testLateCancelledDeliveryCannotReleaseNewHop() {
        let model = AppModel()
        let cancelled = model.internetHop.begin()
        let current = model.internetHop.begin()
        model.endInternetHop(cancelled)
        XCTAssertTrue(model.internetHop.owns(current))
        model.endInternetHop(current)
        XCTAssertFalse(model.internetHopActive)
    }

    func testStaleTransferredRequestCannotAdoptNewHop() async {
        let model = AppModel()
        let old = model.internetHop.begin()
        let current = model.internetHop.begin()
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .frameio, configuration: .init(), internetHopToken: old)
        let outcome = await MediaDeliveryRunner.execute(request: request, model: model) { _ in
            XCTFail("A stale request must stop before presenting progress")
        }
        guard case .failed(let message) = outcome else { return XCTFail("Expected cancellation") }
        XCTAssertEqual(message, "Cancelled.")
        XCTAssertTrue(model.internetHop.owns(current))
        model.endInternetHop(current)
    }

    func testFrameioRequestWithoutTransferCannotAdoptUnrelatedHop() async {
        let model = AppModel()
        let unrelated = model.internetHop.begin()
        let request = MediaDeliveryBeginRequest(
            files: [], destination: .frameio, configuration: .init())
        _ = await MediaDeliveryRunner.execute(request: request, model: model) { _ in
            XCTFail("An empty request must fail before presenting progress")
        }
        XCTAssertTrue(model.internetHop.owns(unrelated))
        model.endInternetHop(unrelated)
    }
}

import XCTest
import OpenPocketViewCore
@testable import MonitorUI

final class PreviewTransferTests: XCTestCase {
    @MainActor
    func testDecodeCallbackFromBeforeResetCannotPresent() async {
        let decoder = HevcDecoder()
        let stalePresent = expectation(description: "Stale frame must not present")
        stalePresent.isInverted = true
        decoder.onPresentedFrame = { stalePresent.fulfill() }
        decoder.reset()
        decoder.handleDecodedFrame(ScopeTestBuffers.makeEdgeBuffer(), expectedGeneration: 0)
        await fulfillment(of: [stalePresent], timeout: 0.2)
        XCTAssertNil(decoder.lastPresentedAt)
    }

    func testRec709IsNotReclassifiedAsLogFromSceneBrightness() async {
        let engine = LiveAssistEngine()
        var effects = LiveImageEffects()
        effects.histogram = true
        let buffer = ScopeTestBuffers.makeBGRA { x, _ in x < 64 ? 16 : 220 }
        let sampled = expectation(description: "Rec.709 scope bundle")
        engine.submit(buffer, effects: effects, transfer: .rec709) { result in
            guard let bundle = result.bundle else { return }
            XCTAssertEqual(result.transfer, .rec709)
            XCTAssertEqual(bundle.transfer, .rec709)
            sampled.fulfill()
        }
        await fulfillment(of: [sampled], timeout: 5)
        engine.reset()
    }
}

import UIKit
import XCTest

@testable import OpenInstaCine

@MainActor
final class VideoDisplayOwnershipTests: XCTestCase {
    func testRetiredHostCannotCloseReplacementDisplayReadiness() {
        let decoder = HevcDecoder()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        let retired = DisplayLayerView(decoder.displayLayer)
        window.addSubview(retired)
        retired.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        retired.layoutSubviews()
        XCTAssertTrue(decoder.isDisplayReady)

        let replacement = DisplayLayerView(decoder.displayLayer)
        window.addSubview(replacement)
        replacement.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        replacement.layoutSubviews()
        let currentOwner = decoder.displayLayer.superlayer
        XCTAssertTrue(replacement.ownsDisplayLayer)
        XCTAssertFalse(retired.ownsDisplayLayer)
        XCTAssertTrue(decoder.isPresentationReady)

        retired.removeFromSuperview()
        window.addSubview(retired)
        XCTAssertNotNil(retired.window)
        XCTAssertFalse(retired.ciFeed.isEnabled)
        XCTAssertTrue(replacement.ciFeed.isEnabled)

        var retiredReadyCalls = 0
        retired.onReady = { retiredReadyCalls += 1 }
        retired.frame = CGRect(x: 0, y: 0, width: 180, height: 320)
        retired.layoutSubviews()
        XCTAssertEqual(decoder.displayLayer.bounds.size, replacement.bounds.size)
        XCTAssertEqual(retiredReadyCalls, 0)

        // SwiftUI may still lay out a retiring host after its layer was adopted
        // by the replacement. Its final zero-size layout must not close recovery.
        retired.frame = .zero
        retired.layoutSubviews()

        XCTAssertTrue(decoder.displayLayer.superlayer === currentOwner)
        XCTAssertEqual(decoder.displayLayer.bounds.size, replacement.bounds.size)
        XCTAssertTrue(decoder.isDisplayReady)
        XCTAssertTrue(decoder.isPresentationReady)

        // The current host must continue to follow real rotation/resize events.
        replacement.frame = CGRect(x: 0, y: 0, width: 360, height: 640)
        replacement.layoutSubviews()
        XCTAssertEqual(decoder.displayLayer.bounds.size, replacement.bounds.size)
        XCTAssertTrue(decoder.isPresentationReady)
        decoder.reset()
    }

    private func singleCameraDisplay(
        _ decoder: HevcDecoder, hdrDisplay: Bool
    ) -> VideoDisplayRepresentable {
        VideoDisplayRepresentable(
            decoder: decoder, effects: LiveImageEffects(), assistMirror: false,
            pictureFlip: false, sampleBus: LiveFrameSampleBus(), transfer: nil,
            feedUpscaler: decoder.feedUpscaler, hdrDisplay: hdrDisplay)
    }
}

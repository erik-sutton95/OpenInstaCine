import UIKit
import XCTest
import MetalKit
import MonitorUI
import OpenCineMedia
import SwiftUI

@testable import OpenInstaCine

@MainActor
final class VideoDisplayOwnershipTests: XCTestCase {
    @MainActor private final class ScopeProbe {
        var view: MTKView?
        var changed: XCTestExpectation?
        func configure(_ view: MTKView, hdr: Bool) -> MonitorScopeDisplayOptions {
            self.view = view
            view.colorPixelFormat = hdr ? .rgba16Float : .bgra8Unorm
            let pending = changed
            changed = nil
            pending?.fulfill()
            return MonitorScopeDisplayOptions(hdr: hdr, gain: hdr ? 2 : 1)
        }
    }

    func testSharedScopeRetainsItsNativeViewAcrossModeSizeAndDisplayChanges() async throws {
        guard MonitorScopeTraceMetal.isAvailable else { throw XCTSkip("Metal is unavailable") }
        let subject = ScopeProbe()
        let peer = ScopeProbe()
        subject.changed = expectation(description: "wave native view configured")
        peer.changed = expectation(description: "vector native view configured")
        let initial = [subject.changed!, peer.changed!]
        let samples = OpenCineMedia.ScopeSamples.empty
        func plot(mode: MonitorScopeTraceMetal.Mode, size: CGSize, hdr: Bool) -> MonitorWaveformScopePlot {
            MonitorWaveformScopePlot(samples: samples, mode: mode, transfer: .rec709,
                clipByte: 255, revision: 1, intensity: 1, size: size,
                configureDisplay: { subject.configure($0, hdr: hdr) })
        }
        let host = UIHostingController(rootView: plot(mode: .waveform(.rgb),
            size: CGSize(width: 250, height: 153), hdr: false))
        let vector = UIHostingController(rootView: MonitorVectorscopeScopePlot(points: [],
            configureDisplay: { peer.configure($0, hdr: false) }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let root = UIViewController()
        window.rootViewController = root
        for (index, child) in [host as UIViewController, vector as UIViewController].enumerated() {
            root.addChild(child)
            root.view.addSubview(child.view)
            child.view.frame = CGRect(x: index * 300, y: 0, width: 280, height: 220)
            child.didMove(toParent: root)
        }
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        root.view.layoutIfNeeded()
        await fulfillment(of: initial, timeout: 5)
        let held = try XCTUnwrap(subject.view)
        let other = try XCTUnwrap(peer.view)
        XCTAssertFalse(held === other)
        XCTAssertEqual(held.colorPixelFormat, .bgra8Unorm)
        subject.changed = expectation(description: "same native view reconfigured")
        let updated = subject.changed!
        host.rootView = plot(mode: .parade(.yrgb), size: CGSize(width: 280, height: 220), hdr: true)
        host.view.frame.size = CGSize(width: 280, height: 220)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await fulfillment(of: [updated], timeout: 5)
        XCTAssertTrue(subject.view === held, "Mode, rotation geometry and display policy retain the MTKView")
        XCTAssertEqual(held.colorPixelFormat, .rgba16Float)
        XCTAssertTrue(peer.view === other)
        XCTAssertEqual(other.colorPixelFormat, .bgra8Unorm, "Another scope retains its own display policy")
    }

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
            pictureFlip: false, sampleBus: LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile), transfer: nil,
            feedUpscaler: decoder.feedUpscaler, hdrDisplay: hdrDisplay)
    }
}

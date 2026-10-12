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

import MonitorUI
import OpenCineCameraControls
import OpenInstaViewCore
import SwiftUI
import UIKit
import Vision

/// SIMULATED source facts, actual shipping popup and native UIKit rendering.
@MainActor
final class MediaDeliveryPresentationTests: XCTestCase {
    func testShareFooterRemainsVisibleAtBothOverflowCardHeights() async throws {
        let model = AppModel()
        let file = MediaFile(
            path: "DCIM/VID_SIMULATED_delivery.MP4", thumbPath: "", sizeBytes: 1_048_576)
        defer { model.session.disconnect() }
        for height: CGFloat in [520, 280] {
            let image = await render(
                AnyView(
                    MediaDeliveryPopup(
                        files: [file], preferredDestination: .nativeShare,
                        maxCardHeight: height, onClose: {}
                    ).environment(model)), name: "shared-delivery-footer-\(Int(height))")
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let labels = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            let normalized = labels.map { $0.lowercased().filter { !$0.isWhitespace } }
            XCTAssertTrue(
                normalized.contains("savetophotos"),
                "The fixed footer must remain visible at \(height): \(labels)")
            XCTAssertFalse(model.delivery.isActive)
            XCTAssertFalse(model.internetHopActive)
        }
    }
    func testSwitchingNetworkKeepsKnownProgressVisibleBesideBusySpinner() async throws {
        let state = MediaDeliveryOverlayState(
            destination: .nativeShare, totalClips: 1,
            clipIndex: 1, clipFraction: 0.5, isSwitchingNetworks: true)
        let image = await render(
            AnyView(MonitorOperatorDeliveryProgress(state: state, onCancel: {})),
            name: "shared-delivery-busy-progress")
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var longest = 0
        // In this app the theme accent is yellow. A long solid run in the right
        // side proves the actual bar, rather than text glyphs or the busy spinner.
        for y in 0..<cg.height {
            var run = 0
            for x in cg.width * 2 / 3..<cg.width {
                let offset = (y * cg.width + x) * 4
                let accent = bytes[offset] > 180 && bytes[offset + 1] > 140 && bytes[offset + 2] < 100
                run = accent ? run + 1 : 0
                longest = max(longest, run)
            }
        }
        XCTAssertGreaterThanOrEqual(
            longest, 16, "Network switching must retain the known half-complete progress bar")
    }
    private func render(_ content: AnyView, name: String) async -> UIImage {
        let size = CGSize(width: 460, height: 600)
        let host = UIHostingController(
            rootView: ZStack(alignment: .bottom) {
                MonitorTheme.background
                content.padding(12)
            }.preferredColorScheme(.dark))
        host.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try? await Task.sleep(for: .milliseconds(400))
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }
}

import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineFrameIOApple
import XCTest

@testable import OpenInstaCine

/// The shared hop owner and delivery coordinator as Insta composes them (A2-16). SIMULATED
/// disconnected sources have no SSID, so the joiner never leaves a network here.
@MainActor
final class MediaDeliveryLifetimeTests: XCTestCase {
    private typealias Token = MonitorInternetHop<InstaHopRoute>.Token

    private func run(_ model: AppModel, _ destination: MonitorDeliveryDestination, lease: Token?) async
        -> MonitorDeliveryCoordinator.Outcome
    {
        await model.delivery.run(
            records: [MediaFile](), destination: destination, action: .systemShare, admission: .init { true },
            source: .init(
                originals: model.clipLibrary().originals, still: { _ in nil }, export: { _, _, _ in nil },
                filename: \.filename, metadata: { _ in nil }),
            includeMetadata: false, remote: nil,
            internet: model.internetHop.deliveryService(route: { model.hopRoute }), lease: lease
        ) { _ in XCTFail("An empty request must fail before presenting progress") }
    }

    func testFrameioPreflightRejectionRestoresTransferredHop() async {
        let model = AppModel()
        defer { model.delivery.close() }
        let token = model.internetHop.begin(model.hopRoute)
        XCTAssertNotNil(token)
        guard case .failed = await run(model, .remoteUpload, lease: token) else {
            return XCTFail("An empty request must fail preflight")
        }
        XCTAssertFalse(model.internetHop.isActive, "Preflight failure must release the transferred hop")
    }

    func testNativePreflightDoesNotAdoptUnrelatedInternetHop() async {
        let model = AppModel()
        defer { model.delivery.close() }
        let token = model.internetHop.begin(model.hopRoute)
        _ = await run(model, .nativeShare, lease: nil)
        XCTAssertTrue(model.internetHop.isActive, "Native export never owns an internet hop")
        if let token { _ = model.internetHop.end(token) }
    }

    func testTransferredPopupCloseCannotReleaseAcceptedDelivery() async {
        let model = AppModel()
        defer { model.delivery.close() }
        let popup = model.internetHop.begin(model.hopRoute)!
        let delivery = model.internetHop.transfer(popup)
        XCTAssertNotNil(delivery)
        XCTAssertNil(model.internetHop.end(popup))
        XCTAssertTrue(model.internetHop.isActive)
        _ = await run(model, .remoteUpload, lease: delivery)
        XCTAssertFalse(model.internetHop.isActive)
    }

    func testASecondHopIsRefusedAndAStaleTokenCannotEndTheRunningOne() {
        let model = AppModel()
        let current = model.internetHop.begin(model.hopRoute)!
        XCTAssertNil(model.internetHop.begin(model.hopRoute), "A running hop is never superseded")
        let transferred = model.internetHop.transfer(current)!
        XCTAssertNil(model.internetHop.end(current))
        XCTAssertTrue(model.internetHop.owns(transferred))
        _ = model.internetHop.end(transferred)
        XCTAssertFalse(model.internetHop.isActive)
    }

    func testStaleTransferredRequestCannotAdoptTheRunningHop() async {
        let model = AppModel()
        defer { model.delivery.close() }
        let old = model.internetHop.begin(model.hopRoute)!
        let current = model.internetHop.transfer(old)!
        guard case .failed = await run(model, .remoteUpload, lease: old) else {
            return XCTFail("A stale request must fail")
        }
        XCTAssertTrue(model.internetHop.owns(current))
        _ = model.internetHop.end(current)
    }

    func testFrameioRequestWithoutTransferCannotAdoptUnrelatedHop() async {
        let model = AppModel()
        defer { model.delivery.close() }
        let unrelated = model.internetHop.begin(model.hopRoute)!
        _ = await run(model, .remoteUpload, lease: nil)
        XCTAssertTrue(model.internetHop.owns(unrelated))
        _ = model.internetHop.end(unrelated)
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
            let popup = model.deliveryPopup(files: [file], preferred: .nativeShare)
            let image = await render(
                AnyView(
                    MonitorOperatorDeliveryScreen(
                        model: popup.model, maxCardHeight: height, onClose: {}, onBegin: popup.begin,
                        remoteArtwork: { FrameioMark() }
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
            XCTAssertFalse(model.internetHop.isActive)
        }
    }
    func testSwitchingNetworkKeepsKnownProgressVisibleBesideBusySpinner() async throws {
        let state = MonitorDeliveryBatchProgress(
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

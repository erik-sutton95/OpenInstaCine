import UIKit
import XCTest
import MetalKit
import MonitorUI
import OpenCineMedia
import SwiftUI

@testable import OpenInstaCine

@MainActor
final class VideoDisplayOwnershipTests: XCTestCase {
    func testSharedTrafficMeterPlacesOverAndUnderBarsAndClearsTheirSuccessor() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 74, height: 168))
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func render(_ reading: ScopeTrafficLightsReading) async throws -> [UInt8] {
            let probe = PanelProbe()
            probe.expectedSize = CGSize(width: 74, height: 168)
            probe.laidOut = expectation(description: "native meter laid out")
            let ready = try XCTUnwrap(probe.laidOut)
            host.rootView = AnyView(ZStack {
                MonitorTrafficLightsMeter(reading: reading)
                PanelProbeView(view: probe).id(ObjectIdentifier(probe)).allowsHitTesting(false)
            }.frame(width: 74, height: 168).ignoresSafeArea()
                .transaction { $0.disablesAnimations = true })
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 5)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let captured = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let image = try XCTUnwrap(captured.cgImage)
            var rgba = [UInt8](repeating: 0, count: 148 * 336 * 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: 148, height: 336,
                bitsPerComponent: 8, bytesPerRow: 148 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 148, height: 336))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "shared-traffic-meter"
            attachment.lifetime = .keepAlways
            add(attachment)
            return rgba
        }
        func pixels(_ rgba: [UInt8], lane: Range<Int>, rows: Range<Int>, component: Int) -> Int {
            var count = 0
            for y in rows { for x in lane {
                let at = (y * 148 + x) * 4
                let dominant = Int(rgba[at + component])
                if dominant > 45 && (0..<3).filter({ $0 != component }).allSatisfy({
                    Double(dominant) > Double(rgba[at + $0]) * 1.4
                }) { count += 1 }
            } }
            return count
        }
        let neutral = try await render(.none)
        let active = try await render(ScopeTrafficLightsReading(
            red: ScopeChannelLight(clip: true, crush: false, level: 0.9),
            green: ScopeChannelLight(clip: false, crush: true, level: 0.1),
            blue: ScopeChannelLight(clip: false, crush: false, level: 0.5)))
        XCTAssertGreaterThan(pixels(active, lane: 18..<47, rows: 85..<173, component: 0)
            - pixels(neutral, lane: 18..<47, rows: 85..<173, component: 0), 300)
        XCTAssertGreaterThan(pixels(active, lane: 59..<89, rows: 185..<280, component: 1)
            - pixels(neutral, lane: 59..<89, rows: 185..<280, component: 1), 300)
        XCTAssertLessThan(pixels(active, lane: 18..<47, rows: 185..<280, component: 0), 10)
        XCTAssertLessThan(pixels(active, lane: 59..<89, rows: 85..<173, component: 1), 10)
        XCTAssertLessThan(pixels(active, lane: 102..<132, rows: 85..<280, component: 2), 10)
        let cleared = try await render(.none)
        XCTAssertEqual(pixels(cleared, lane: 18..<47, rows: 85..<173, component: 0),
            pixels(neutral, lane: 18..<47, rows: 85..<173, component: 0))
        XCTAssertEqual(pixels(cleared, lane: 59..<89, rows: 185..<280, component: 1),
            pixels(neutral, lane: 59..<89, rows: 185..<280, component: 1))
    }

    func testSharedAspectMaskLeavesBothGuideArmsClearAndOnlyDimsTheirExterior() throws {
        let feed = CGRect(x: 20, y: 20, width: 320, height: 180)
        let renderer = ImageRenderer(content: ZStack(alignment: .topLeading) {
            Color.blue
            MonitorAspectGuideFrames(selectedRatios: [.cinema, .vertical], maskEnabled: true, feed: feed)
        }.frame(width: 360, height: 220))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var rgba = [UInt8](repeating: 0, count: 360 * 220 * 4)
        let context = try XCTUnwrap(CGContext(data: &rgba, width: 360, height: 220,
            bitsPerComponent: 8, bytesPerRow: 360 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 220)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 360, height: 220))
        func blue(_ x: Int, _ y: Int) -> UInt8 { rgba[(y * 360 + x) * 4 + 2] }
        XCTAssertTrue((95...110).contains(blue(32, 32)))
        XCTAssertGreaterThan(blue(180, 110), 240)
        XCTAssertGreaterThan(blue(180, 22), 240)
        XCTAssertGreaterThan(blue(30, 110), 240)
        XCTAssertGreaterThan(blue(5, 5), 240)
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = "shared-guide-union-mask"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private final class PanelProbe: UIView {
        var expectedSize = CGSize.zero
        var laidOut: XCTestExpectation?
        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size == expectedSize {
                let pending = laidOut
                laidOut = nil
                pending?.fulfill()
            }
        }
    }
    @MainActor private struct PanelProbeView: UIViewRepresentable {
        let view: PanelProbe
        func makeUIView(context: Context) -> PanelProbe { view }
        func updateUIView(_ uiView: PanelProbe, context: Context) { uiView.setNeedsLayout() }
    }

    func testSharedMovablePanelRetainsNativeContentAndFitsProtectedGeometry() async throws {
        let probe = PanelProbe()
        probe.backgroundColor = .red
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for canvas in [CGRect(x: 0, y: 0, width: 874, height: 402),
            CGRect(x: 0, y: 0, width: 402, height: 874)] {
            let movement = MonitorScopePanelPlacement.bounds(in: canvas,
                clearance: EdgeInsets(top: 64, leading: 0, bottom: 96, trailing: 74))
            let layout = MonitorScopePanelLayout(baseSize: MonitorScopePanelSize.waveform,
                preferredSize: CGSize(width: 400, height: 245), center: CGPoint(x: 4000, y: 4000),
                scale: 1.6, canvas: canvas, movementBounds: movement)
            probe.expectedSize = layout.size
            probe.laidOut = expectation(description: "actual panel content laid out")
            let ready = probe.laidOut!
            window.frame = canvas
            host.rootView = AnyView(MonitorMovableScopePanel(layout: layout, resizeLabel: "Resize scope",
                onMove: { _ in XCTFail("Layout must not persist a drag") },
                onResize: { _ in XCTFail("Layout must not rewrite the scale") }) {
                    PanelProbeView(view: probe)
                }.ignoresSafeArea())
            host.view.frame = canvas
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 5)
            XCTAssertTrue(probe.window === window)
            let frame = probe.convert(probe.bounds, to: host.view)
            XCTAssertEqual(frame.width, layout.size.width, accuracy: 1)
            XCTAssertEqual(frame.height, layout.size.height, accuracy: 1)
            XCTAssertEqual(frame.midX, layout.center.x, accuracy: 1)
            XCTAssertEqual(frame.midY, layout.center.y, accuracy: 1)
            XCTAssertGreaterThanOrEqual(frame.minX, movement.minX)
            XCTAssertGreaterThanOrEqual(frame.minY, movement.minY)
            XCTAssertLessThanOrEqual(frame.maxX, movement.maxX)
            XCTAssertLessThanOrEqual(frame.maxY + MonitorScopePanelPlacement.gripBottomExtent, movement.maxY)
        }
    }

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

import OpenCineApple
import UIKit
import XCTest
import MetalKit
import MonitorUI
import OpenCineCameraControls
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI

@testable import OpenInstaCine

@MainActor
final class VideoDisplayOwnershipTests: XCTestCase {
    /// SIMULATED marks exercise the actual native renderer and retained hosting controller.
    func testSharedTrackingMarksRenderProjectedEdgesAndClearAnEmptySuccessor() async throws {
        let size = CGSize(width: 300, height: 200)
        let feed = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .black
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func render(_ rect: CGRect?, focus: MonitorFocusMark?, name: String) async throws -> [UInt8] {
            let probe = PanelProbe()
            probe.expectedSize = size
            probe.laidOut = expectation(description: "native tracking marks laid out")
            let ready = try XCTUnwrap(probe.laidOut)
            let marks = rect.map { [MonitorTrackingBracketValue(normalizedRect: $0, color: .green)] } ?? []
            host.rootView = AnyView(ZStack(alignment: .topLeading) {
                Color.black
                ZStack {
                    MonitorTrackingLayer(brackets: marks, focus: focus, feed: feed)
                    PanelProbeView(view: probe).id(ObjectIdentifier(probe)).allowsHitTesting(false)
                }.frame(width: size.width, height: size.height)
            }.ignoresSafeArea().transaction { $0.disablesAnimations = true })
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 5)
            let displayed = expectation(description: "native tracking marks submitted")
            let frames = NativeFrameProbe(ready: displayed)
            frames.start()
            await fulfillment(of: [displayed], timeout: 5)
            frames.stop()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let origin = probe.convert(CGPoint.zero, to: host.view)
            let image = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: CGRect(x: -origin.x, y: -origin.y,
                    width: host.view.bounds.width, height: host.view.bounds.height), afterScreenUpdates: true))
            }.cgImage)
            var rgba = [UInt8](repeating: 0, count: 300 * 200 * 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: 300, height: 200,
                bitsPerComponent: 8, bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: feed)
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "SIMULATED-shared-tracking-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return rgba
        }
        func pixels(_ rgba: [UInt8], columns: Range<Int>, rows: Range<Int>, channel: Int) -> Int {
            var count = 0
            for y in rows { for x in columns {
                let offset = (y * 300 + x) * 4
                let rgb = (0..<3).map { Int(rgba[offset + $0]) }
                if rgb[channel] > 100 && (0..<3).filter({ $0 != channel })
                    .allSatisfy({ rgb[channel] - rgb[$0] > 80 }) { count += 1 }
            } }
            return count
        }
        let active = try await render(CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4),
            focus: MonitorFocusMark(point: CGPoint(x: 0.8, y: 0.45), color: .red, aeLocked: true, focusLocked: true),
            name: "active")
        XCTAssertGreaterThan(pixels(active, columns: 55..<86, rows: 55..<91, channel: 1), 40)
        XCTAssertEqual(pixels(active, columns: 99..<112, rows: 58..<63, channel: 1), 0,
            "Bracket arms must leave the upper center open")
        XCTAssertGreaterThan(pixels(active, columns: 200..<281, rows: 65..<111, channel: 0), 20)
        let projected = try await render(CGRect(x: 0.5, y: 0.3, width: 0.3, height: 0.4), focus: nil, name: "projected")
        XCTAssertEqual(pixels(projected, columns: 55..<86, rows: 55..<91, channel: 1), 0)
        XCTAssertGreaterThan(pixels(projected, columns: 145..<176, rows: 55..<91, channel: 1), 40)
        XCTAssertEqual(pixels(projected, columns: 200..<281, rows: 65..<111, channel: 0), 0,
            "Retired focus and its lock tags must clear")
        let cleared = try await render(nil, focus: nil, name: "cleared")
        XCTAssertEqual(pixels(cleared, columns: 0..<300, rows: 0..<200, channel: 1), 0)
    }

    func testSharedNDChipClearsTheAccentWhenPictureMeasurementDisappears() async throws {
        let size = CGSize(width: 84, height: 30)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .black
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func render(_ reading: MonitorNDFilterSuggestion?, name: String) async throws -> [UInt8] {
            let probe = PanelProbe()
            probe.expectedSize = size
            probe.laidOut = expectation(description: "native ND chip laid out")
            let ready = try XCTUnwrap(probe.laidOut)
            host.rootView = AnyView(ZStack(alignment: .topLeading) {
                Color.black
                ZStack {
                    NDMeterChip(reading: reading)
                    PanelProbeView(view: probe).id(ObjectIdentifier(probe)).allowsHitTesting(false)
                }.frame(width: size.width, height: size.height)
            }.ignoresSafeArea())
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 5)
            let displayed = expectation(description: "native ND chip submitted")
            let frames = NativeFrameProbe(ready: displayed)
            frames.start()
            await fulfillment(of: [displayed], timeout: 5)
            frames.stop()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let origin = probe.convert(CGPoint.zero, to: host.view)
            let image = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: CGRect(x: -origin.x, y: -origin.y,
                    width: host.view.bounds.width, height: host.view.bounds.height), afterScreenUpdates: true))
            }.cgImage)
            var rgba = [UInt8](repeating: 0, count: 168 * 60 * 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: 168, height: 60,
                bitsPerComponent: 8, bytesPerRow: 672, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 168, height: 60))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "shared-ND-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return rgba
        }
        func accentPixels(_ rgba: [UInt8]) -> Int {
            var count = 0
            for index in stride(from: 0, to: rgba.count, by: 4) {
                let red = Int(rgba[index]), green = Int(rgba[index + 1]), blue = Int(rgba[index + 2])
                if max(red, green, blue) - min(red, green, blue) > 80 { count += 1 }
            }
            return count
        }
        let hot = try await render(
            MonitorNDFilterRecommendation.suggestion(pictureStops: 6, noneLabel: NDAssist.noneLabel),
            name: "hot")
        XCTAssertGreaterThan(accentPixels(hot), 100)
        let absent = try await render(nil, name: "absent")
        XCTAssertEqual(accentPixels(absent), 0)
        let knownZero = try await render(
            MonitorNDFilterRecommendation.suggestion(pictureStops: 0, noneLabel: NDAssist.noneLabel),
            name: "zero")
        XCTAssertEqual(accentPixels(knownZero), 0)
    }

    func testSharedLevelOverlayClearsKnownGreenAndReplacesBubbleWithUnavailable() async throws {
        let size = CGSize(width: 300, height: 300)
        let feed = CGRect(origin: .zero, size: size)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .black
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func render(_ display: MonitorLevelDisplay, name: String) async throws -> [UInt8] {
            let probe = PanelProbe()
            probe.expectedSize = size
            probe.laidOut = expectation(description: "native level overlay laid out")
            let ready = try XCTUnwrap(probe.laidOut)
            host.rootView = AnyView(ZStack(alignment: .topLeading) {
                Color.black
                ZStack {
                    MonitorLevelOverlay(display: display, feed: feed, viewport: feed, portrait: true)
                    PanelProbeView(view: probe).id(ObjectIdentifier(probe)).allowsHitTesting(false)
                }.frame(width: size.width, height: size.height)
            }.ignoresSafeArea().transaction { $0.disablesAnimations = true })
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 5)
            let displayed = expectation(description: "native level canvas submitted")
            let frames = NativeFrameProbe(ready: displayed)
            frames.start()
            await fulfillment(of: [displayed], timeout: 5)
            frames.stop()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let origin = probe.convert(CGPoint.zero, to: host.view)
            let image = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: CGRect(x: -origin.x, y: -origin.y,
                    width: host.view.bounds.width, height: host.view.bounds.height), afterScreenUpdates: true))
            }.cgImage)
            var rgba = [UInt8](repeating: 0, count: 300 * 300 * 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: 300, height: 300,
                bitsPerComponent: 8, bytesPerRow: 1200, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: feed)
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "shared-level-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return rgba
        }
        func greenPixels(_ rgba: [UInt8]) -> Int {
            var count = 0
            for index in stride(from: 0, to: rgba.count, by: 4) {
                let red = Int(rgba[index]), green = Int(rgba[index + 1]), blue = Int(rgba[index + 2])
                if green > 100 && green > red * 2 && green > blue * 3 / 2 { count += 1 }
            }
            return count
        }
        let gauges = try await render(.gauges(rollDeg: 0, tiltDeg: 0), name: "known-zero")
        XCTAssertGreaterThan(greenPixels(gauges), 100)
        let unavailable = try await render(.unavailable, name: "unavailable")
        XCTAssertEqual(greenPixels(unavailable), 0)
        let bubble = try await render(.bubble(xDeg: 0, yDeg: 0), name: "known-bubble")
        XCTAssertGreaterThan(greenPixels(bubble), 40)
        let retired = try await render(.unavailable, name: "retired-bubble")
        XCTAssertEqual(greenPixels(retired), 0)
        XCTAssertEqual(LevelAssist.accessibilityValue(.unavailable), WorldLevelSnap.noLevelData)
        XCTAssertEqual(LevelAssist.accessibilityValue(.gauges(rollDeg: 1.5, tiltDeg: -0.3)),
            "Roll +1.5°, tilt -0.3°")
    }

    func testSharedAudioMeterRotatesItsTracksKeepsPeaksAndClearsSilentSuccessor() async throws {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .black
        host.safeAreaRegions = []
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func render(_ orientation: MonitorAudioOrientation, silent: Bool) async throws -> [UInt8] {
            let size = MonitorAudioMetrics.panelSize(orientation: orientation)
            let probe = PanelProbe()
            probe.expectedSize = size
            probe.laidOut = expectation(description: "native audio meter laid out")
            let ready = try XCTUnwrap(probe.laidOut)
            host.rootView = AnyView(ZStack(alignment: .topLeading) {
                Color.black
                ZStack {
                MonitorAudioMeter(left: silent ? -60 : -3, leftPeak: silent ? -60 : 0,
                    right: silent ? -60 : -30, rightPeak: silent ? -60 : -18,
                    orientation: orientation)
                PanelProbeView(view: probe).id(ObjectIdentifier(probe)).allowsHitTesting(false)
                }.frame(width: size.width, height: size.height)
            }.ignoresSafeArea())
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await fulfillment(of: [ready], timeout: 5)
            let displayed = expectation(description: "native audio canvas submitted")
            let frames = NativeFrameProbe(ready: displayed)
            frames.start()
            await fulfillment(of: [displayed], timeout: 5)
            frames.stop()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let origin = probe.convert(CGPoint.zero, to: host.view)
            let captured = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: CGRect(x: -origin.x, y: -origin.y,
                    width: host.view.bounds.width, height: host.view.bounds.height), afterScreenUpdates: true))
            }
            let image = try XCTUnwrap(captured.cgImage)
            let width = Int(size.width * 2), height = Int(size.height * 2)
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "shared-audio-\(orientation.rawValue)-\(silent ? "silent" : "active")"
            attachment.lifetime = .keepAlways
            add(attachment)
            return rgba
        }
        for orientation in MonitorAudioOrientation.allCases {
            let width = Int(MonitorAudioMetrics.panelSize(orientation: orientation).width * 2)
            func channels(_ rgba: [UInt8], _ point: CGPoint) -> [Int] {
                let at = (Int((point.y * 2).rounded()) * width + Int((point.x * 2).rounded())) * 4
                return (0..<3).map { Int(rgba[at + $0]) }
            }
            let vertical = orientation == .vertical
            let redPoint = vertical ? CGPoint(x: 8, y: 13) : CGPoint(x: 155, y: 8)
            let greenPoint = vertical ? CGPoint(x: 20, y: 120) : CGPoint(x: 35, y: 20)
            let emptyPoint = vertical ? CGPoint(x: 20, y: 30) : CGPoint(x: 100, y: 20)
            let peakPoint = vertical ? CGPoint(x: 20, y: 49) : CGPoint(x: 120, y: 20)
            let active = try await render(orientation, silent: false)
            let red = channels(active, redPoint), green = channels(active, greenPoint)
            XCTAssertGreaterThan(red[0], 200)
            XCTAssertLessThan(red[1], 140)
            XCTAssertGreaterThan(green[1], 150)
            XCTAssertLessThan(green[0], 120)
            let empty = channels(active, emptyPoint)
            XCTAssertLessThan(abs(empty[0] - empty[1]), 4)
            let peak = channels(active, peakPoint)
            XCTAssertGreaterThan(peak[0], 150)
            XCTAssertGreaterThan(peak[1], 120)
            XCTAssertLessThan(peak[2], 110)
            let silent = try await render(orientation, silent: true)
            for point in [redPoint, greenPoint, peakPoint] {
                let clear = channels(silent, point)
                XCTAssertLessThan(abs(clear[0] - clear[1]), 4)
                XCTAssertLessThan(abs(clear[1] - clear[2]), 4)
            }
        }
    }

    func testSharedFalseColorReferenceRetainsResolvedKeyRendersGapsAndClearsSuccessor() throws {
        var source = [MonitorFalseColorReferenceSegment(id: 0, lowerFraction: 0, upperFraction: 0.25,
            red: 1, green: 0, blue: 0),
            MonitorFalseColorReferenceSegment(id: 1, lowerFraction: 0.75, upperFraction: 1,
                red: 0, green: 0, blue: 1)]
        let held = MonitorFalseColorReferenceValues(subtitle: "Source A", segments: source,
            axisLabels: ["crush", "18%", "clip"])
        source.removeAll()
        let successor = MonitorFalseColorReferenceValues(subtitle: "Source B", segments: source)
        func render(_ values: MonitorFalseColorReferenceValues) throws -> [UInt8] {
            let renderer = ImageRenderer(content: MonitorFalseColorReference(values: values, inspector: true)
                .frame(width: 250, height: 26).background(Color.black))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage?.cgImage)
            var rgba = [UInt8](repeating: 0, count: 250 * 26 * 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: 250, height: 26,
                bitsPerComponent: 8, bytesPerRow: 250 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 250, height: 26))
            let attachment = XCTAttachment(image: UIImage(cgImage: image))
            attachment.name = "shared-false-color-reference"
            attachment.lifetime = .keepAlways
            add(attachment)
            return rgba
        }
        func channel(_ rgba: [UInt8], _ x: Int, _ component: Int) -> Int { Int(rgba[(7 * 250 + x) * 4 + component]) }
        let image = try render(held)
        XCTAssertGreaterThan(channel(image, 20, 0), 240)
        XCTAssertLessThan(channel(image, 20, 1), 10)
        XCTAssertLessThan(channel(image, 20, 2), 10)
        XCTAssertGreaterThan(channel(image, 230, 2), 240)
        XCTAssertLessThan(channel(image, 230, 0), 10)
        XCTAssertLessThan(channel(image, 230, 1), 10)
        XCTAssertLessThan(abs(channel(image, 125, 0) - channel(image, 125, 1)), 4)
        XCTAssertGreaterThan(channel(image, 125, 0), 100)
        let cleared = try render(successor)
        for x in [20, 125, 230] {
            XCTAssertLessThan(abs(channel(cleared, x, 0) - channel(cleared, x, 1)), 4)
            XCTAssertLessThan(abs(channel(cleared, x, 1) - channel(cleared, x, 2)), 4)
        }
    }

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

    @MainActor private final class NativeFrameProbe: NSObject {
        let ready: XCTestExpectation
        private var remaining = 2
        private var link: CADisplayLink?
        init(ready: XCTestExpectation) { self.ready = ready }
        func start() {
            link = CADisplayLink(target: self, selector: #selector(frame))
            link?.add(to: .main, forMode: .common)
        }
        func stop() { link?.invalidate(); link = nil }
        @objc private func frame() {
            remaining -= 1
            if remaining == 0 { stop(); ready.fulfill() }
        }
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

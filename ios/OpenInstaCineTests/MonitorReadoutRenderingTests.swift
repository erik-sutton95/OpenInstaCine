import Insta360AppleTestSupport
import Insta360Protocol
import SwiftUI
import XCTest

@testable import MonitorUI
@testable import OpenInstaCine

/// The status chrome on this app's model. The drum and shadow cases are in MonitorUITests.
@MainActor
final class MonitorReadoutRenderingTests: XCTestCase {
    func testPortraitStorageRendersOutsideTheRasterizedStatusBand() async throws {
        let model = AppModel()
        model.session.status.storageFreeMb = 102_400
        let camera = FakeLuna()
        let session = camera.connectedSession()
        let volume = try ProtoMessage.integer(field: 2, value: 107_374_182_400)
            + ProtoMessage.integer(field: 3, value: 137_438_953_472)
            + ProtoMessage.integer(field: 4, value: 2)
        session.ingest(device: try LunaDeviceStatus(response:
            ProtoMessage.blob(field: 2, value: ProtoMessage.blob(field: 176, value: volume))))
        model.control.bind(session)
        defer { model.control.unbind() }
        for _ in 0..<100 where model.control.snapshot?.storage.value == nil { await Task.yield() }
        XCTAssertEqual(model.control.snapshot?.storage.value?.first?.freeBytes.value, 107_374_182_400,
            "The native fixture renders the same storage through the common Luna observation")
        let layout = LiveMonitorLayout.fieldMonitor(
            size: CGSize(width: 440, height: 956),
            safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0),
            sourceAspect: 16 / 9, fill: false, showsValues: true, showsBottomBars: true)
        let renderer = ImageRenderer(
            content: ZStack(alignment: .topLeading) {
                Color.black
                FieldMonitorStatusChrome(menu: .constant(nil), layout: layout)
                    .frame(width: layout.topDeck.width)
                    .position(x: layout.topDeck.midX, y: layout.topDeck.midY)
            }
            .frame(width: 440, height: 956)
            .environment(model))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let bytes = try rgba(image)
        let whitePixels = (0..<90).reduce(0) { count, y in
            count
                + (10..<180).filter { x in
                    let index = (y * image.width + x) * 4
                    return bytes[index] > 220 && bytes[index + 1] > 220 && bytes[index + 2] > 220
                }.count
        }
        XCTAssertGreaterThan(
            whitePixels, 100,
            "Storage must remain visible in the header, above the lower status band's raster bounds"
        )
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

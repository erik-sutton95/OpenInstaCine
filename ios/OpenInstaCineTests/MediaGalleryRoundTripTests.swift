import Foundation
import MonitorPresentation
import OpenCineAppKit
import OpenInstaViewCore
import SwiftUI
import UIKit
import XCTest

@testable import OpenInstaCine

/// SIMULATED cached stills in the actual gallery and its actual fullScreenCover round trip.
@MainActor final class MediaGalleryRoundTripTests: XCTestCase {
    func testGalleryKeepsScrollOffsetAcrossACoverInGrid() async throws { try await assertRoundTrip(.grid) }
    func testGalleryKeepsScrollOffsetAcrossACoverInList() async throws { try await assertRoundTrip(.list) }
    func testChangedLayoutDoesNotInheritTheOutgoingPosition() async throws {
        try await assertRoundTrip(.grid, returning: .list)
        try await assertRoundTrip(.list, returning: .grid)
    }

    private func assertRoundTrip(_ layout: MonitorMediaLayout, returning: MonitorMediaLayout? = nil) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let media = CameraMedia(cacheRoot: root)
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder(),
            cameraMedia: media, controlsOnly: true)
        let model = AppModel(session: session)
        defer {
            model.delivery.close(); session.disconnect()
            try? FileManager.default.removeItem(at: root)
        }
        let owner = try XCTUnwrap(session.mediaLibrary)
        let files = (0..<48).map { index in
            MediaFile(path: String(format: "/DCIM/Camera01/SIMULATED_%04d.JPG", index), thumbPath: "", sizeBytes: 4)
        }
        let records = try LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil }).decode(JSONEncoder().encode(files))
        for record in records {
            let original = try XCTUnwrap(record.asset.representations.first { $0.role == .original })
            try owner.cache.directory.write(Data([0xFF, 0xD8, 0xFF, 0xD9]), at: try XCTUnwrap(record.address.representations[original.id]))
        }
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: records), token: owner.actionToken)
        owner.layout = layout
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: MediaLibraryView().environment(model))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 420)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.frame = window.bounds
        let ready = await settled {
            host.view.layoutIfNeeded()
            return Self.scrollViews(host.view).contains { $0.contentSize.height > $0.bounds.height + 500 }
        }
        XCTAssertTrue(ready, "The cached stills must fill a scrolling gallery")
        let scroll = try XCTUnwrap(Self.scrollViews(host.view).first { $0.contentSize.height > $0.bounds.height + 500 })
        scroll.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        host.view.layoutIfNeeded()
        let before = scroll.contentOffset.y
        XCTAssertGreaterThan(before, 300, "The gallery must start the round trip scrolled")
        let visible: () -> NSObject? = {
            Self.objects(host.view).first {
                Self.identifier($0)?.hasPrefix("monitor.media.clip.") == true
                    && $0.accessibilityFrame.intersects(scroll.convert(scroll.bounds, to: nil))
            }
        }
        _ = await settled { host.view.layoutIfNeeded(); return visible() != nil }
        let element = try XCTUnwrap(visible(), "A visible gallery item must be reachable")
        XCTAssertTrue(element.accessibilityActivate(), "The visible item must open through accessibility")
        let presented = await settled { host.presentedViewController != nil }
        XCTAssertTrue(presented, "Opening an item must present its cover")
        if let returning { owner.layout = returning }
        host.dismiss(animated: false)
        let dismissed = await settled { host.presentedViewController == nil }
        XCTAssertTrue(dismissed)
        host.view.layoutIfNeeded()
        let returned = try XCTUnwrap(Self.scrollViews(host.view).first {
            $0.window != nil && $0.contentSize.height > $0.bounds.height + 500
        })
        if returning == nil {
            XCTAssertEqual(returned.contentOffset.y, before, accuracy: 1, "Closing a cover must keep the gallery position")
        } else {
            XCTAssertEqual(returned.contentOffset.y, -returned.adjustedContentInset.top, accuracy: 1,
                "A changed layout must not inherit the outgoing layout's position")
        }
    }

    private func settled(_ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        return predicate()
    }
    private static func scrollViews(_ view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }
    private static func objects(_ object: NSObject) -> [NSObject] {
        if object.accessibilityElementsHidden { return [] }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return [] }
        let children: [NSObject]
        if let values = object.accessibilityElements as? [NSObject], !values.isEmpty {
            children = values
        } else {
            let count = object.accessibilityElementCount()
            children = count > 0 && count != NSNotFound
                ? (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
                : (object as? UIView)?.subviews ?? []
        }
        return [object] + children.flatMap(objects)
    }
    private static func identifier(_ object: NSObject) -> String? {
        let getter = NSSelectorFromString("accessibilityIdentifier")
        guard object.responds(to: getter) else { return nil }
        return object.perform(getter)?.takeUnretainedValue() as? String
    }
}

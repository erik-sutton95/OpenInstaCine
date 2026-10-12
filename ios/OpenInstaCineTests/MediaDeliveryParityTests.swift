import Foundation
import OpenCineAppKit
import OpenInstaViewCore
import SwiftUI
import UIKit
import XCTest

@testable import OpenInstaCine

/// SIMULATED cached files and disconnected sessions over the shipping delivery composition.
@MainActor final class MediaDeliveryParityTests: XCTestCase {
    /// A2-06: a cached still is shared as its original, never through the movie exporter.
    func testCachedPhotoSharesItsOriginalWithoutAMovieExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let media = CameraMedia(cacheRoot: root)
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder(),
            cameraMedia: media, controlsOnly: true)
        let model = AppModel(session: session)
        defer {
            model.delivery.close()
            session.disconnect()
            try? FileManager.default.removeItem(at: root)
        }
        let photo = MediaFile(path: "/DCIM/Camera01/SIMULATED_0001.JPG", thumbPath: "", sizeBytes: 4)
        let url = media.fileCacheURL(cameraID: session.mediaCameraID, file: photo)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: url)
        XCTAssertTrue(session.isDownloaded(photo))
        var configuration = MediaDeliveryConfiguration()
        configuration.bakeLUT = false
        let outcome = await MediaDeliveryRunner.execute(
            request: .init(files: [photo], destination: .nativeShare, configuration: configuration),
            model: model) { _ in }
        guard case .share(let urls, _, _) = outcome else {
            return XCTFail("A cached photo must reach the share sheet, got \(outcome)")
        }
        XCTAssertEqual(urls.map(\.standardizedFileURL), [url.standardizedFileURL])
    }

    /// A2-05: Frame.io from the camera network caches first; an uncached clip keeps the route.
    func testFrameioHopFromAnUncachedSelectionStaysOnTheCameraNetwork() async throws {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        let clip = MediaFile(path: "/DCIM/Camera01/SIMULATED_0002.MP4", thumbPath: "", sizeBytes: 1_000)
        let source = MediaDeliveryPreparationSource(model: model, files: [clip], preferredDestination: .frameio)
        defer { source.preparation.close() }
        source.preparation.hopToInternet()
        for _ in 0..<200 where source.preparation.projectsError == nil && !model.internetHopActive {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.internetHopActive, "An uncached clip must not leave the camera network")
        XCTAssertNotNil(source.preparation.projectsError)
    }

    /// A2-04: a delivery outcome is announced in the gallery and at the root.
    func testGalleryAnnouncesADeliveryOutcome() async throws {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        try await assertAnnounced(MediaLibraryView().environment(model), model: model)
    }

    func testRootAnnouncesADeliveryOutcomeWithoutAMediaSurface() async throws {
        let model = AppModel()
        defer { model.delivery.close(); model.session.disconnect() }
        try await assertAnnounced(LinkExperience().environment(model), model: model)
    }

    private func assertAnnounced(_ view: some View, model: AppModel) async throws {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        try XCTSkipIf(Self.labels(host.view).isEmpty, "No accessibility tree: enable app accessibility")
        model.delivery.failUnavailableExportSettings()
        var announced = false
        for _ in 0..<60 where !announced {
            try await Task.sleep(for: .milliseconds(50))
            host.view.layoutIfNeeded()
            announced = Self.labels(host.view).contains("Export settings are unavailable.")
        }
        XCTAssertTrue(announced, "The failed delivery's outcome must be visible")
    }

    private static func labels(_ object: NSObject, depth: Int = 0) -> [String] {
        guard depth < 64, !object.accessibilityElementsHidden else { return [] }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return [] }
        let own = object.accessibilityLabel.map { [$0] } ?? []
        if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
            return own + elements.flatMap { labels($0, depth: depth + 1) }
        }
        return own + ((object as? UIView)?.subviews ?? []).flatMap { labels($0, depth: depth + 1) }
    }
}

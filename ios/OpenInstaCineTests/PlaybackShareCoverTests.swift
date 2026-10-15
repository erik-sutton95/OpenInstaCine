import AVFoundation
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineApple
import OpenCineMedia
import OpenInstaViewCore
import SwiftUI
import UIKit
import XCTest

@testable import OpenInstaCine

/// SIMULATED delivery run held open by the test, so the share outcome lands while the player is up.
@MainActor private final class ShareCoverGate {
    private var waiter: CheckedContinuation<MonitorDeliveryCoordinator.Outcome, Never>?
    var waiting: Bool { waiter != nil }
    func wait() async -> MonitorDeliveryCoordinator.Outcome {
        await withCheckedContinuation { waiter = $0 }
    }
    func release(_ outcome: MonitorDeliveryCoordinator.Outcome) {
        waiter?.resume(returning: outcome); waiter = nil
    }
}

/// SIMULATED six second flat H.264 clip, long enough that a resumed player is still playing.
@MainActor private final class ShareCoverClip {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("simulated-share-cover-\(UUID().uuidString).mp4")
    private let frames = 180
    private var frame = 0
    private var done: CheckedContinuation<Void, Never>?

    func write() async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var created: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
        let buffer = try XCTUnwrap(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x80, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            done = continuation
            input.requestMediaDataWhenReady(on: .main) { [self] in
                MainActor.assumeIsolated {
                    while input.isReadyForMoreMediaData, frame < frames {
                        adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
                        frame += 1
                    }
                    guard frame == frames, let done else { return }
                    self.done = nil
                    input.markAsFinished()
                    done.resume()
                }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

/// A2-71: a finished delivery whose share sheet is still up covers playback exactly like a
/// running delivery. SIMULATED cached clip in the shipping player and the app's own coordinator.
@MainActor final class PlaybackShareCoverTests: XCTestCase {
    func testPendingShareKeepsPlaybackPausedUntilTheSheetCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder(),
            cameraMedia: CameraMedia(cacheRoot: root), controlsOnly: true)
        let model = AppModel(session: session)
        let clip = ShareCoverClip()
        defer {
            model.delivery.close(); session.disconnect()
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: clip.url)
        }
        try await clip.write()
        let bytes = try Data(contentsOf: clip.url)
        let owner = try XCTUnwrap(session.mediaLibrary)
        let files = [MediaFile(path: "/DCIM/Camera01/SIMULATED_SHARE_COVER.MP4", thumbPath: "", sizeBytes: UInt64(bytes.count))]
        let record = try XCTUnwrap(LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
            .decode(JSONEncoder().encode(files)).first)
        let original = try XCTUnwrap(record.asset.representations.first { $0.role == .original })
        try owner.cache.directory.write(bytes, at: try XCTUnwrap(record.address.representations[original.id]))
        let cached = session.cameraMedia.fileCacheURL(cameraID: session.mediaCameraID, file: record.payload.file)
        if !FileManager.default.fileExists(atPath: cached.path) {
            try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: cached)
        }
        try owner.applyLocalRecords(.init(resetLibrary: true, upserts: [record]), token: owner.actionToken)
        // The gallery begins its library before it opens a record; the player opens from there.
        owner.begin()
        let browsing = await settled { owner.browsing && !owner.fetching && owner.record(record.asset.id) != nil }
        XCTAssertTrue(browsing, "The cached record must stay in the begun library")
        let captured = try XCTUnwrap(owner.record(record.asset.id))
        let opening = MonitorMediaGalleryOpen(record: captured, playlist: [captured], admission: owner.actionToken)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow
        let host = UIHostingController(rootView: MediaPlayerView(opening: opening).environment(model)
            .environment(\.scenePhase, .active))
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds; window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        var player: AVPlayer? { Self.picture(in: window)?.playerLayer.player }
        let playing = await settled(timeout: 10) { (player?.rate ?? 0) > 0 }
        if !playing { attach(window, "SIMULATED-playback-not-playing") }
        XCTAssertTrue(playing, "The cached clip must start playing in the shipping player: \(Self.diagnose(window))")
        let native = try XCTUnwrap(player)
        attach(window, "SIMULATED-playback-playing")

        let gate = ShareCoverGate()
        model.delivery.begin { _, _ in await gate.wait() }
        let paused = await settled { gate.waiting && native.rate == 0 }
        XCTAssertTrue(paused, "A running delivery covers playback")

        // The run ends in a share the app root has not presented and acknowledged: the sheet is up.
        gate.release(.share(urls: [clip.url], metadataText: nil, stagingCleanupURL: nil))
        let shared = await settled { model.delivery.lifetime.state.share != nil && !model.delivery.isActive }
        XCTAssertTrue(shared, "The finished run leaves its share pending")
        let resumedBehindSheet = await settled(timeout: 1.5) { native.rate > 0 }
        XCTAssertFalse(resumedBehindSheet, "A2-71: playback must stay paused behind the pending share sheet")
        attach(window, "SIMULATED-playback-share-pending")

        model.delivery.lifetime.clearSharePresentation()
        let resumed = await settled { native.rate > 0 }
        XCTAssertTrue(resumed, "Completing the share sheet uncovers playback")
    }

    private func settled(timeout: TimeInterval = 5, _ predicate: @escaping @MainActor () -> Bool) async -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { predicate() }
        }, object: nil)
        return await XCTWaiter.fulfillment(of: [expectation], timeout: timeout) == .completed
    }

    private func attach(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name + "-" + UIDevice.current.userInterfaceIdiom.attachmentName
        attachment.lifetime = .keepAlways; add(attachment)
    }

    private static func diagnose(_ window: UIWindow) -> String {
        let player = picture(in: window)?.playerLayer.player
        let item = player?.currentItem
        let ids = Set(objects(window).compactMap(identifier)).sorted()
        return "picture=\(picture(in: window) != nil) item=\(item.map { String($0.status.rawValue) } ?? "nil")"
            + " error=\(String(describing: item?.error)) rate=\(player?.rate ?? -1)"
            + " control=\(player.map { String($0.timeControlStatus.rawValue) } ?? "nil")"
            + " ids=\(ids.prefix(60))"
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
        return (object.perform(getter)?.takeUnretainedValue() as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func picture(in view: UIView) -> MonitorPlaybackFeedHost? {
        if let host = view as? MonitorPlaybackFeedHost, host.accessibilityIdentifier == "monitor.native.picture" { return host }
        for child in view.subviews { if let found = picture(in: child) { return found } }
        return nil
    }
}

private extension UIUserInterfaceIdiom {
    var attachmentName: String { self == .pad ? "tablet" : "phone" }
}

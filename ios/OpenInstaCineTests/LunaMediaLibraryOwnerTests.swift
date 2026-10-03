import Foundation
import OpenCineCore
import OpenCineAppKit
import OpenCineMedia
import OpenPocketViewCore
import XCTest
@testable import OpenInstaCine

@MainActor private final class GalleryCursor: MediaCatalogCursor {
    var finished = false
    func next() async -> MediaCatalogDelta? {
        guard !finished else { return nil }; finished = true
        return .init(complete: true)
    }
    func close() { finished = true }
}
@MainActor private final class GalleryBrowse: CameraMediaBrowse {
    let binding = MediaBrowseBinding(session: .init(), epoch: .init(1))
    var thumbnails: (any CameraMediaThumbnailService)? { nil }
    var transfers: (any CameraMediaTransferService)? { nil }
    var deletion: (any CameraMediaDeleteService)? { nil }
    var closes = 0
    func catalog() async -> any MediaCatalogCursor { GalleryCursor() }
    func close() async { closes += 1 }
}
@MainActor private final class GalleryService: CameraMediaService {
    let browse = GalleryBrowse()
    var sessionID: OpenCineCore.CameraSessionID { browse.binding.session }
    var opens = 0
    func openBrowse() async -> any CameraMediaBrowse { opens += 1; return browse }
}

@MainActor private final class GalleryPlaybackPort: MonitorPlaybackPort {
    var onEvent: (@MainActor @Sendable (MonitorPlaybackItemToken, MonitorPlaybackEvent) -> Void)?
    var prepared: [MonitorPlaybackItem] = []
    var token: MonitorPlaybackItemToken?
    var closes = 0
    var held = false
    var pending: CheckedContinuation<MonitorPlaybackMetadata, Error>?
    func retireItem(for token: MonitorPlaybackItemToken) { self.token = token }
    func prepare(_ item: MonitorPlaybackItem, token: MonitorPlaybackItemToken, readyTimeout: Duration?) async throws -> MonitorPlaybackMetadata {
        prepared.append(item)
        if held { return try await withCheckedThrowingContinuation { pending = $0 } }
        return .init(duration: 2)
    }
    func release() { pending?.resume(returning: .init(duration: 2)); pending = nil }
    func play(rate: Double, token: MonitorPlaybackItemToken) {}
    func pause(token: MonitorPlaybackItemToken) {}
    func seek(seconds: Double, tolerance: Double, token: MonitorPlaybackItemToken) async -> Bool { true }
    func setMuted(_ muted: Bool, token: MonitorPlaybackItemToken) {}
    func close(token: MonitorPlaybackItemToken) { if self.token?.owner == token.owner { closes += 1; onEvent = nil } }
}

/// Exercises the real app factory and outer cover hook with its actual shared owner.
@MainActor final class LunaMediaLibraryOwnerTests: XCTestCase {
    private func session(root: URL, storage: MonitorMediaCacheStorage) -> OpenInstaCine.CameraSession {
        OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder(),
            cameraMedia: CameraMedia(storage: storage, cacheRoot: root), controlsOnly: true)
    }
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "The owned operation did not settle")
    }
    private func seedPlayback(_ session: OpenInstaCine.CameraSession) throws -> MediaFile {
        let file = MediaFile(path: "/DCIM/VID_fixture.MP4", thumbPath: "", sizeBytes: 4, durationSeconds: 2,
            resolution: "1920x1080", fps: 30, proxyPath: "/DCIM/LRV_fixture.LRV")
        let directory = session.cameraMedia.directory(cameraID: session.mediaCameraID)
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let bytes = try JSONEncoder().encode([file]), record = try XCTUnwrap(codec.decode(bytes).first)
        try directory.write(bytes, at: "index.json")
        for address in record.address.representations.values { try directory.write(Data([1, 2, 3, 4]), at: address) }
        session.resetMediaSession()
        return file
    }
    func testActualPlaybackFactoryPrefersCachedProxyAndBorrowsTheGallery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MonitorMediaCacheStorage(), seed = session(root: root, storage: storage)
        let file = try seedPlayback(seed)
        seed.cameraMedia.rememberShotColor(.iLog, path: file.path, cameraID: seed.mediaCameraID)
        let session = session(root: root, storage: storage), native = GalleryPlaybackPort()
        session.beginMediaBrowse()
        let record = try XCTUnwrap(session.mediaPlaybackRecord(for: file)), library = try XCTUnwrap(session.mediaLibrary)
        let playback = session.makeMediaPlayback(native: native, previousColor: { .normal })
        playback.load(record, playlist: [record]); await settle { playback.ready && playback.look != nil }
        let prepared = try XCTUnwrap(native.prepared.first)
        XCTAssertEqual(prepared.role, .proxy); XCTAssertEqual(prepared.sourceKey, file.proxyPath)
        XCTAssertEqual(prepared.url, session.localProxySource(for: file)?.url)
        XCTAssertEqual(playback.look?.source.color, .iLog)
        XCTAssertEqual(playback.look?.source.shotColor, .iLog)
        XCTAssertEqual(session.shotColor(for: file), .iLog)
        XCTAssertEqual(native.prepared.count, 1)
        playback.close(); XCTAssertTrue(library.browsing); XCTAssertEqual(native.closes, 1)
        session.endMediaBrowse()
    }
    func testActualOuterGalleryHookRetiresPendingBorrowedPlaybackOnlyOnExit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MonitorMediaCacheStorage(), seed = session(root: root, storage: storage)
        let file = try seedPlayback(seed)
        let session = session(root: root, storage: storage), native = GalleryPlaybackPort()
        native.held = true
        let model = AppModel(session: session)
        model.shell.open(.media); session.beginMediaBrowse()
        let library = try XCTUnwrap(session.mediaLibrary), lifetime = library.lifetimeToken
        let record = try XCTUnwrap(session.mediaPlaybackRecord(for: file))
        let playback = session.makeMediaPlayback(native: native, previousColor: { nil })
        playback.load(record, playlist: [record]); await settle { native.pending != nil }
        model.noteMediaCoverChanged(from: .media, to: .media); session.beginMediaBrowse()
        XCTAssertEqual(library.lifetimeToken, lifetime); XCTAssertFalse(playback.closed); XCTAssertEqual(native.closes, 0)
        model.shell.dismissCover(); model.noteMediaCoverChanged(from: .media, to: nil)
        await settle { playback.closed }; native.release(); await Task.yield()
        XCTAssertFalse(playback.ready || library.browsing); XCTAssertEqual(native.closes, 1)
    }

    func testActualOuterCoverHookRetainsOneBrowseThroughBorrowedCoversThenClosesOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = session(root: root, storage: MonitorMediaCacheStorage())
        let model = AppModel(session: session), service = GalleryService()
        session.configureMediaLibrary(service: service)
        let library = try XCTUnwrap(session.mediaLibrary)
        model.shell.open(.media); session.beginMediaBrowse()
        await settle { library.binding != nil && !library.fetching }
        let binding = library.binding
        model.noteMediaCoverChanged(from: .media, to: .media)
        session.beginMediaBrowse(); session.beginMediaBrowse()
        XCTAssertTrue(session.mediaLibrary === library)
        XCTAssertEqual(library.binding, binding)
        XCTAssertEqual(service.opens, 1); XCTAssertEqual(service.browse.closes, 0)
        model.shell.dismissCover(); model.noteMediaCoverChanged(from: .media, to: nil)
        XCTAssertFalse(library.browsing); XCTAssertNil(library.binding)
        await settle { service.browse.closes == 1 }
        model.noteMediaCoverChanged(from: nil, to: nil); session.endMediaBrowse()
        await Task.yield()
        XCTAssertEqual(service.browse.closes, 1)
    }
    func testActualFactorySharesRootRegistryAcrossSessionReplacementAndClearFencesOldWriter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MonitorMediaCacheStorage()
        let old = session(root: root, storage: storage), next = session(root: root, storage: storage)
        let directory = old.mediaLibrary.cache.directory
        XCTAssertTrue(directory === next.mediaLibrary.cache.directory)
        try directory.write(Data("[]".utf8), at: "index.json")
        let writer = try directory.beginWrite(at: "files/take.mp4")
        try await writer.write(Data([1]))
        try await next.clearMediaCache()
        let current = try directory.beginWrite(at: "files/take.mp4")
        try await current.write(Data([2]))
        _ = try current.commit(.init(byteCount: 1))
        do { try await writer.write(Data([3])); XCTFail("Retired source cannot write into successor root") }
        catch let error as MonitorMediaCacheError { XCTAssertEqual(error, .retired) }
        writer.abort()
        XCTAssertEqual(try directory.read("files/take.mp4"), Data([2]))
        XCTAssertEqual(try directory.read("index.json"), Data("[]".utf8))
        old.resetMediaSession(); next.resetMediaSession()
    }
}

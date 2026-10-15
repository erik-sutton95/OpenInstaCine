import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineCore
import OpenCineAppKit
import OpenCineMedia
import OpenInstaViewCore
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
    let binding: MediaBrowseBinding
    init(session: OpenCineCore.CameraSessionID = .init()) {
        binding = MediaBrowseBinding(session: session, epoch: .init(1))
    }
    var thumbnails: (any CameraMediaThumbnailService)? { nil }
    var transfers: (any CameraMediaTransferService)? { nil }
    var deletion: (any CameraMediaDeleteService)? { nil }
    var closes = 0
    func catalog() async -> any MediaCatalogCursor { GalleryCursor() }
    func close() async { closes += 1 }
}
@MainActor private final class GalleryService: CameraMediaService {
    let browse: GalleryBrowse
    init(session: OpenCineCore.CameraSessionID = .init()) { browse = GalleryBrowse(session: session) }
    var sessionID: OpenCineCore.CameraSessionID { browse.binding.session }
    var opens = 0
    func openBrowse() async -> any CameraMediaBrowse { opens += 1; return browse }
}

/// SIMULATED: immutable metadata captured at the real catalog codec boundary.
@MainActor private final class GammaCatalogRecordSource: LunaMediaCatalogRecordSource {
    let binding = MediaBrowseBinding(session: .init(), epoch: .init(1))
    let record: LunaMediaCatalogRecord

    init(label: String?) throws {
        var bytes = try ProtoMessage.integer(field: 9, value: 4)
        if let label { bytes += try ProtoMessage.blob(field: 22, value: Data(label.utf8)) }
        record = .init(
            asset: .init("SIMULATED-gamma"),
            file: .init(uri: "/DCIM/SIMULATED-gamma.MP4", metadata: try LunaFileMetadata(bytes)))
    }

    func mediaCatalogRecord(_ asset: MediaAssetID, binding: MediaBrowseBinding) -> LunaMediaCatalogRecord? {
        self.binding == binding && record.asset == asset ? record : nil
    }
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

    /// SIMULATED: both real consumers preserve the original aliases, priority and unknowns.
    func testActualCatalogAndPlaybackAgreeOnCapturedGammaMetadata() async throws {
        let cases: [(String?, ColorMode?)] = [
            ("I-Log", .iLog), ("ilog", .iLog), ("LOG HDR", .iLog),
            ("Dolby Vision", .dolbyVision), ("HDR", .dolbyVision),
            ("Standard", .normal), ("VIVID", .normal), ("standard vivid", .normal),
            (nil, nil), ("", nil), ("flat", nil), ("unknown", nil),
        ]
        for (label, expected) in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let current = session(root: root, storage: MonitorMediaCacheStorage())
            defer {
                current.endMediaBrowse()
                current.decoder.close()
                try? FileManager.default.removeItem(at: root)
            }
            let source = try GammaCatalogRecordSource(label: label)
            let codec = LunaMediaCatalogCodec(source: source, shotColor: { _ in nil })
            let asset = MediaAsset(
                id: source.record.asset, filename: "SIMULATED-gamma.MP4", durationSeconds: 2,
                representations: [.init(id: .init("original"), role: .original, byteCount: 4)])
            let record = try codec.capture(asset, binding: source.binding)
            XCTAssertEqual(record.facts.color, expected.map { String($0.rawValue) }, "Catalog: \(label ?? "nil")")

            let library = try XCTUnwrap(current.mediaLibrary)
            try library.applyLocalRecords(.init(resetLibrary: true, upserts: [record]), token: library.actionToken)
            for address in record.address.representations.values {
                try library.cache.directory.write(Data([1, 2, 3, 4]), at: address)
            }
            current.beginMediaBrowse()
            let native = GalleryPlaybackPort()
            let playback = current.makeMediaPlayback(native: native, previousColor: { .normal })
            defer { playback.close() }
            playback.load(record, playlist: [record])
            await settle { playback.ready && playback.look != nil }
            XCTAssertEqual(playback.look?.source.shotColor, expected, "Playback: \(label ?? "nil")")
            XCTAssertEqual(native.prepared.count, 1)
            XCTAssertEqual(playback.look?.source.file, record.payload.file)
            XCTAssertEqual(record.payload.source?.metadata?.gammaMode, label)
        }
    }

    /// SIMULATED: an observed shot color still takes precedence over fallback metadata.
    func testActualConsumersKeepShotColorAheadOfGammaMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = session(root: root, storage: MonitorMediaCacheStorage())
        defer {
            current.endMediaBrowse()
            current.decoder.close()
            try? FileManager.default.removeItem(at: root)
        }
        let source = try GammaCatalogRecordSource(label: "standard")
        let codec = LunaMediaCatalogCodec(source: source, shotColor: { _ in .iLog })
        let asset = MediaAsset(
            id: source.record.asset, filename: "SIMULATED-gamma.MP4", durationSeconds: 2,
            representations: [.init(id: .init("original"), role: .original, byteCount: 4)])
        let record = try codec.capture(asset, binding: source.binding)
        XCTAssertEqual(record.facts.color, String(ColorMode.iLog.rawValue))
        current.cameraMedia.rememberShotColor(
            .iLog, path: record.payload.file.path, cameraID: current.mediaCameraID)
        let library = try XCTUnwrap(current.mediaLibrary)
        try library.applyLocalRecords(.init(resetLibrary: true, upserts: [record]), token: library.actionToken)
        for address in record.address.representations.values {
            try library.cache.directory.write(Data([1, 2, 3, 4]), at: address)
        }
        current.beginMediaBrowse()
        let native = GalleryPlaybackPort()
        let playback = current.makeMediaPlayback(native: native, previousColor: { .normal })
        defer { playback.close() }
        playback.load(record, playlist: [record])
        await settle { playback.ready && playback.look != nil }
        XCTAssertEqual(playback.look?.source.shotColor, .iLog)
        XCTAssertEqual(playback.look?.source.color, .iLog)
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

    /// SIMULATED: drive the real app phase callback and shared gallery, retaining an uncached catalogue.
    func testHeldLiveRecoveryReopensRegisteredServiceWithoutReplacingRetainedCatalogue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MonitorMediaCacheStorage(), seed = session(root: root, storage: storage)
        let file = MediaFile(path: "/DCIM/VID_SIMULATED_recovery.MP4", thumbPath: "", sizeBytes: 99,
            durationSeconds: 2, resolution: "1920x1080", fps: 30)
        try seed.cameraMedia.directory(cameraID: seed.mediaCameraID)
            .write(JSONEncoder().encode([file]), at: "index.json")
        let current = session(root: root, storage: storage), model = AppModel(session: current)
        defer { current.endMediaBrowse(); model.shell.close(); seed.endMediaBrowse() }
        let library = try XCTUnwrap(current.mediaLibrary)
        let retainedIDs = library.records.map(\.asset.id)
        XCTAssertEqual(retainedIDs.count, 1)
        XCTAssertTrue(library.libraryRecords.isEmpty, "The retained uncached row is unavailable without a source")
        XCTAssertTrue(library.cache.directory === seed.mediaLibrary.cache.directory)
        var camera = ChromeEditorReturnTests.camera(model)
        let service = GalleryService(session: camera.session.id)
        camera.services.register(service, as: (any CameraMediaService).self)
        model.shell.present(camera); model.noteMonitorChanged()
        let monitorID = try XCTUnwrap(model.shell.monitor?.id)
        current.beginMediaBrowse()
        await settle { library.binding == service.browse.binding && !library.fetching }
        XCTAssertEqual(service.opens, 1)
        XCTAssertEqual(library.libraryRecords.map(\.asset.id), retainedIDs)
        current.endMediaBrowse()
        await settle { service.browse.closes == 1 }

        // Connection preparation retires the service while the same monitor and cache survive.
        current.configureMediaLibrary()
        current.holdsMonitor = true; current.phase = .connectingGatt
        model.noteLinkPhase()
        XCTAssertFalse(library.canRefresh)
        XCTAssertEqual(library.records.map(\.asset.id), retainedIDs)
        XCTAssertTrue(library.libraryRecords.isEmpty)
        current.phase = .live; model.noteLinkPhase()
        XCTAssertTrue(library.canRefresh, "A ready kept session must restore its registered media service")
        XCTAssertTrue(current.mediaLibrary === library)
        XCTAssertTrue(library.cache.directory === seed.mediaLibrary.cache.directory)
        XCTAssertEqual(model.shell.monitor?.id, monitorID)
        XCTAssertEqual(current.mediaLibraryServiceID, camera.session.id)
        current.beginMediaBrowse()
        await settle { service.opens == 2 && library.binding == service.browse.binding && !library.fetching }
        XCTAssertEqual(library.records.map(\.asset.id), retainedIDs)
        XCTAssertEqual(library.libraryRecords.map(\.asset.id), retainedIDs)
        let lifetime = library.lifetimeToken
        model.noteLinkPhase(); current.beginMediaBrowse(); await Task.yield()
        XCTAssertEqual(service.opens, 2)
        XCTAssertEqual(library.lifetimeToken, lifetime)
        XCTAssertEqual(library.binding?.session, camera.session.id)
    }

    /// SIMULATED: a failed held connection cannot restore a browse merely because the monitor remains.
    func testHeldNonLiveRecoveryKeepsMediaUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = session(root: root, storage: MonitorMediaCacheStorage()), model = AppModel(session: current)
        defer { current.endMediaBrowse(); model.shell.close() }
        var camera = ChromeEditorReturnTests.camera(model)
        let service = GalleryService(session: camera.session.id)
        camera.services.register(service, as: (any CameraMediaService).self)
        model.shell.present(camera); model.noteMonitorChanged()
        let library = try XCTUnwrap(current.mediaLibrary), monitorID = try XCTUnwrap(model.shell.monitor?.id)
        current.configureMediaLibrary(); current.holdsMonitor = true; current.phase = .failed("SIMULATED recovery")
        model.noteLinkPhase(); current.beginMediaBrowse(); await Task.yield()
        XCTAssertEqual(model.shell.monitor?.id, monitorID)
        XCTAssertTrue(current.mediaLibrary === library)
        XCTAssertFalse(library.canRefresh)
        XCTAssertNil(library.binding)
        XCTAssertEqual(service.opens, 0)
    }

    /// SIMULATED: a live monitor without a registered media service stays unsupported.
    func testUnregisteredLiveMonitorDoesNotInventMediaService() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = session(root: root, storage: MonitorMediaCacheStorage()), model = AppModel(session: current)
        defer { current.endMediaBrowse(); model.shell.close() }
        model.shell.present(ChromeEditorReturnTests.camera(model)); model.noteMonitorChanged()
        let library = try XCTUnwrap(current.mediaLibrary), monitorID = try XCTUnwrap(model.shell.monitor?.id)
        current.holdsMonitor = true; current.phase = .live
        model.noteLinkPhase(); current.beginMediaBrowse(); await Task.yield()
        XCTAssertEqual(model.shell.monitor?.id, monitorID)
        XCTAssertTrue(current.mediaLibrary === library)
        XCTAssertFalse(library.canRefresh)
        XCTAssertNil(library.binding)
        XCTAssertNil(current.mediaLibraryServiceID)
    }
}

import Foundation
import OpenCineCore
import OpenCineAppKit
import OpenCineMedia
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

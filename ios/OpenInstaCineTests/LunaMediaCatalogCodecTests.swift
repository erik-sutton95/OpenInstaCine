import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineCore
import OpenCineAppKit
import OpenCineMedia
import OpenInstaViewCore
import XCTest
@testable import OpenInstaCine

@MainActor private final class CatalogRecordSource: LunaMediaCatalogRecordSource {
    var binding = MediaBrowseBinding(session: .init(), epoch: .init(1))
    var record: LunaMediaCatalogRecord?
    func mediaCatalogRecord(_ asset: MediaAssetID, binding: MediaBrowseBinding) -> LunaMediaCatalogRecord? {
        self.binding == binding && record?.asset == asset ? record : nil
    }
}

@MainActor final class LunaMediaCatalogCodecTests: XCTestCase {
    private func file(starred: Bool = false, storage: Int = 0) -> MediaFile {
        .init(path: "/storage_internal/DCIM/Camera01/VID_20260916_124229_002.mp4",
            thumbPath: "/storage_internal/DCIM/Camera01/thumb.jpg", handle: 1, cmdHandle: 27,
            sizeBytes: 99, durationSeconds: 7, isStarred: starred, resolution: "1920x1080", fps: 30,
            proxyPath: "/storage_internal/DCIM/Camera01/LRV_20260916_124229_002.lrv", storage: storage,
            storageKnown: nil, group: 4, handleShared: true, handleCandidate: 29)
    }
    private func bytes(_ files: [MediaFile]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(files)
    }
    func testLegacyBytesFieldsAndAddressesStayCompatible() throws {
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let original = try bytes([file()]), records = try codec.decode(original)
        XCTAssertEqual(try codec.encode(records), original)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.payload.file, file())
        XCTAssertNil(record.payload.source)
        XCTAssertEqual(record.address.favoriteKey, file().path)
        XCTAssertEqual(record.address.thumbnail, "thumbs/_storage_internal_DCIM_Camera01_thumb.jpg.jpg")
        let originalID = try XCTUnwrap(record.asset.representations.first { $0.role == .original }?.id)
        XCTAssertEqual(record.address.representations[originalID], "files/_storage_internal_DCIM_Camera01_VID_20260916_124229_002.mp4")
        XCTAssertEqual(record.facts.dateKey, "20260916")
        XCTAssertEqual(record.facts.orderKey, "20260916124229")
    }
    func testLoadingUnknownRawFieldsNeverRewritesIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let cache = MonitorMediaCache(directory: .init(root: root), codec: codec,
            eligibility: .minimumFraction(numerator: 9, denominator: 10), catalogAddress: "index.json",
            preservedMetadata: ["index.json", "color.json"])
        let raw = try bytes([file()])
        let text = String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "[{", with: "[{\"unknownRaw\":{\"code\":19},")
        let preserved = Data(text.utf8)
        try cache.directory.write(preserved, at: "index.json")
        XCTAssertEqual(cache.load().map(\.payload.file), [file()])
        XCTAssertEqual(try cache.directory.read("index.json"), preserved)
    }
    func testOfflineContentIdentitySeparatesVolumesAndIgnoresLocalFavoriteChanges() throws {
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let ids = try codec.decode(bytes([file(storage: 1), file(storage: 2)])).map(\.asset.id)
        XCTAssertNotEqual(ids[0], ids[1])
        let first = try XCTUnwrap(codec.decode(bytes([file()])).first?.asset.id)
        let starred = try XCTUnwrap(codec.decode(bytes([file(starred: true)])).first?.asset.id)
        XCTAssertEqual(first, starred)
    }
    func testCapturedRawPayloadSurvivesBrowseReplacementBeforeEncoding() async throws {
        let source = CatalogRecordSource(), id = MediaAssetID("opaque-A")
        let metadata = try LunaFileMetadata(ProtoMessage.integer(field: 9, value: 99)
            + ProtoMessage.blob(field: 22, value: Data("log".utf8)))
        let raw = LunaMediaFile(uri: file().path, metadata: metadata)
        source.record = .init(asset: id, file: raw)
        let binding = source.binding
        let codec = LunaMediaCatalogCodec(source: source, shotColor: { _ in nil })
        let asset = MediaAsset(id: id, filename: "A.mp4", representations: [
            .init(id: .init("original-A"), role: .original, byteCount: 99)])
        let captured = try codec.capture(asset, binding: binding)
        await Task.yield()
        source.binding = .init(session: binding.session, epoch: binding.epoch)
        source.record = .init(asset: id, file: .init(uri: raw.uri,
            metadata: try LunaFileMetadata(ProtoMessage.integer(field: 9, value: 1000))))
        XCTAssertEqual(captured.payload.source, raw)
        XCTAssertEqual(try JSONDecoder().decode([MediaFile].self, from: codec.encode([captured])).first?.sizeBytes, 99)
        XCTAssertThrowsError(try codec.capture(asset, binding: binding))
    }
    func testUnfavoriteSurvivesLegacyCatalogReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferencesName = "opc.media-codec-test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: preferencesName))
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: preferencesName) }
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let preferences = MonitorMediaPreferences(storage: defaults, favoriteKey: "favorite", lastCameraKey: "last")
        let cache = MonitorMediaCache(directory: .init(root: root), codec: codec,
            eligibility: .minimumFraction(numerator: 9, denominator: 10), catalogAddress: "index.json",
            preservedMetadata: ["index.json", "color.json"])
        try cache.directory.write(bytes([file(starred: true)]), at: "index.json")
        let original = MonitorMediaLibraryModel(cache: cache, favorites: preferences)
        original.toggleFavorite(try XCTUnwrap(original.records.first?.asset.id)); original.close()
        let reloaded = MonitorMediaLibraryModel(cache: cache, favorites: preferences)
        defer { reloaded.close() }
        XCTAssertEqual(reloaded.records.first?.favorite, false)
    }
}

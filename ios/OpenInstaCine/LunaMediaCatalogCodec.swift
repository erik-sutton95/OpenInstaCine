import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineAppKit
import OpenCineMedia
import OpenInstaViewCore

/// The common library owns catalog/workflows; this preservation value keeps the actual source
/// metadata beside the unchanged legacy index record for source look and playback adapters.
struct LunaMediaLibraryPayload: Sendable {
    let file: MediaFile
    let source: LunaMediaFile?
}

@MainActor final class LunaMediaCatalogCodec: MonitorMediaCatalogCodec {
    typealias Payload = LunaMediaLibraryPayload
    private weak var source: (any LunaMediaCatalogRecordSource)?
    private let shotColor: (MediaFile) -> ColorMode?
    init(source: (any LunaMediaCatalogRecordSource)?, shotColor: @escaping (MediaFile) -> ColorMode?) {
        self.source = source; self.shotColor = shotColor
    }
    func decode(_ bytes: Data) throws -> [MonitorMediaRecord<Payload>] {
        try JSONDecoder().decode([MediaFile].self, from: bytes).map { file in
            let id = try offlineIdentity(file)
            var representations = [MediaRepresentation(id: .init(id.rawValue + ":original"), role: .original,
                byteCount: file.sizeBytes > 0 ? file.sizeBytes : nil)]
            if file.proxyPath != nil { representations.append(.init(id: .init(id.rawValue + ":proxy"), role: .proxy)) }
            let kind: MediaAssetKind = switch file.kind { case .video: .video; case .photo: .photo }
            let asset = MediaAsset(id: id, filename: file.filename, kind: kind, capturedAt: file.captureDate,
                durationSeconds: file.durationSeconds > 0 ? Double(file.durationSeconds) : nil,
                frameRate: file.fps.flatMap { $0 > 0 ? Double($0) : nil }, representations: representations)
            return record(asset, payload: .init(file: file, source: nil))
        }
    }
    func encode(_ records: [MonitorMediaRecord<Payload>]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(records.map { record in
            var file = record.payload.file; file.isStarred = record.favorite
            return file
        })
    }
    func capture(_ asset: MediaAsset, binding: MediaBrowseBinding) throws -> MonitorMediaRecord<Payload> {
        // This synchronous lookup is restricted to the producing browse/asset. No later catalog
        // or replacement backend can substitute A's immutable raw record while encoding yields.
        guard let captured = source?.mediaCatalogRecord(asset.id, binding: binding) else { throw MediaServiceError.retired }
        return record(asset, payload: .init(file: CameraSession.mediaFile(captured.file), source: captured.file))
    }
    private func record(_ asset: MediaAsset, payload: Payload) -> MonitorMediaRecord<Payload> {
        let file = payload.file
        var addresses: [MediaRepresentationID: String] = [:]
        for representation in asset.representations {
            switch representation.role {
            case .original: addresses[representation.id] = "files/" + cacheName(file.path)
            case .proxy:
                if let path = file.proxyPath { addresses[representation.id] = "play/" + MediaHTTP.playbackCacheFileName(path) }
            }
        }
        return .init(asset: asset, payload: payload, address: .init(
            thumbnail: "thumbs/" + cacheName(file.thumbPath) + ".jpg", representations: addresses, favoriteKey: file.path),
            favorite: file.isStarred, facts: .init(format: file.fileExtension, resolution: file.resolution,
                dateKey: file.dateKey.isEmpty ? nil : file.dateKey, orderKey: file.filenameTimestamp,
                color: (shotColor(file) ?? LunaColorMode(gammaLabel: payload.source?.metadata?.gammaMode)
                    .map(LunaShellMapping.colorMode)).map { String($0.rawValue) }))
    }
    private func cacheName(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "_") }
    private func offlineIdentity(_ file: MediaFile) throws -> MediaAssetID {
        // Offline records have no live content token. Their complete legacy content facts form
        // an app-owned namespace, distinct from every freshly observed source identity.
        var content = file; content.isStarred = false
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return .init("legacy-index:" + (try encoder.encode(content)).base64EncodedString())
    }
}

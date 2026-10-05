import Foundation
import Insta360Protocol
import OpenCineAppKit
import OpenCineMedia
import OpenPocketViewCore

/// Operator-facing media notes. Never name a sister app or another camera brand.
enum MediaOperatorCopy {
    static let listing = "Listing camera clips…"
    static let notConnected = "Connect the camera to list clips."
    static let playbackFailed = "Camera did not enter playback."
    static let browsingOnCamera = "Playback is open on the camera. Close to return to live view."
    static let noClips = "No clips on the camera."
    static let listFailed = "Could not list camera clips."
    static let notDeletable = "That clip cannot be deleted from here."
    static let deleteFailed = "Could not delete that clip."
    static let downloadFailed = "Could not download that clip."
    static let thumbFailed = "Could not load that thumbnail."
    static let clipOpenFailed = "Could not open that clip."
    static let clipLoading = "Loading clip from camera…"
    static let clipNotCached = "This clip is not cached on the phone."
}

/// App-owned cache namespace and source look metadata. Catalog, favorites, clearing and
/// bounded transfer lifetimes are owned by OpenCineAppKit and OpenCineApple.
@MainActor final class CameraMedia {
    private let fileManager: FileManager
    let storage: MonitorMediaCacheStorage
    let nativeIO: LunaNativeMediaIO
    private let rootOverride: URL?
    private var storageWinner: [String: Int] = [:]
    private var colorMapCache: (cameraID: String, map: [String: Int])?
    init(fileManager: FileManager = .default, httpConfiguration: URLSessionConfiguration = .ephemeral,
        storage: MonitorMediaCacheStorage? = nil, cacheRoot: URL? = nil) {
        self.fileManager = fileManager; self.storage = storage ?? MonitorMediaCacheStorage(fileManager: fileManager)
        nativeIO = LunaNativeMediaIO(configuration: httpConfiguration); rootOverride = cacheRoot
        #if DEBUG && targetEnvironment(simulator)
            MonitorMediaReview.prepareOwnedIndex()
        #endif
    }
    func cacheRoot(cameraID: String) -> URL {
        if let rootOverride { return rootOverride.appendingPathComponent(cameraID, isDirectory: true) }
        #if DEBUG && targetEnvironment(simulator)
            if MonitorMediaReview.isActive { return MonitorMediaReview.cacheRoot }
        #endif
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenInstaCine/media/\(cameraID)", isDirectory: true)
    }
    func directory(cameraID: String) -> MonitorMediaCacheDirectory { storage.directory(root: cacheRoot(cameraID: cameraID)) }
    func thumbnailCacheURL(cameraID: String, file: MediaFile) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent("thumbs/" + cacheName(file.thumbPath) + ".jpg")
    }
    func fileCacheURL(cameraID: String, file: MediaFile) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent("files/" + cacheName(file.path))
    }
    func playbackAddress(file: MediaFile, path: String) -> String {
        path == file.path ? "files/" + cacheName(file.path) : "play/" + MediaHTTP.playbackCacheFileName(path)
    }
    func playbackCacheURL(cameraID: String, file: MediaFile, path: String) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent(playbackAddress(file: file, path: path))
    }
    func cacheByteCount(cameraID: String) async -> UInt64 { await directory(cameraID: cameraID).totalByteCount() }
    func resolvedStorage(for file: MediaFile, singleSd: Bool) -> Int {
        MediaHTTP.resolvedStorage(stamped: file.storage, handle: file.handle != 0 ? file.handle : file.cmdHandle,
            winner: storageWinner[file.path], singleSdStorage: singleSd)
    }
    func rememberStorage(_ storage: Int, for path: String) { storageWinner[path] = storage }
    private func cacheName(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "_") }
    func colorStoreURL(cameraID: String) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent("color.json")
    }

    func shotColor(for path: String, cameraID: String) -> ColorMode? {
        migrateLegacyShotColors(cameraID: cameraID)
        guard let raw = loadColorMap(cameraID: cameraID)[path],
            let mode = ColorMode(rawValue: UInt8(truncatingIfNeeded: raw))
        else { return nil }
        return mode
    }

    func rememberShotColor(_ color: ColorMode, path: String, cameraID: String) {
        migrateLegacyShotColors(cameraID: cameraID)
        var map = loadColorMap(cameraID: cameraID)
        map[path] = Int(color.rawValue)
        persistColorMap(map, cameraID: cameraID)
    }

    private func loadColorMap(cameraID: String) -> [String: Int] {
        if let cached = colorMapCache, cached.cameraID == cameraID { return cached.map }
        let url = colorStoreURL(cameraID: cameraID)
        let map: [String: Int]
        if let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        {
            map = decoded
        } else {
            map = [:]
        }
        colorMapCache = (cameraID, map)
        return map
    }

    private func persistColorMap(_ map: [String: Int], cameraID: String) {
        colorMapCache = (cameraID, map)
        let url = colorStoreURL(cameraID: cameraID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(map)
            try data.write(to: url, options: .atomic)
        } catch {
            ControlLiveLog.line("media: color store write failed \(error.localizedDescription)")
        }
    }

    private func migrateLegacyShotColors(cameraID: String) {
        let legacyKey = "OpenInstaCine.ClipShotColor"
        guard let raw = UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: Int],
            !raw.isEmpty
        else { return }
        var map = loadColorMap(cameraID: cameraID)
        for (path, code) in raw where map[path] == nil {
            map[path] = code
        }
        persistColorMap(map, cameraID: cameraID)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    nonisolated static func existingFile(
        _ url: URL, fileManager: FileManager = .default
    ) -> URL? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
            !isDir.boolValue
        else { return nil }
        if let size = try? fileManager.attributesOfItem(atPath: url.path)[.size]
            as? NSNumber,
            size.intValue <= 0
        {
            return nil
        }
        return url
    }

}

enum MediaTransferError: Error { case badResponse, httpStatus(Int), timeout }
struct MediaPlaybackSource: Equatable {
    var url: URL
    var mimeType: String
    var isRemote: Bool
    var path: String
}

/// Small source/playback compatibility adapters. The gallery consumes mediaLibrary directly.
extension CameraSession {
    func configureMediaLibrary(service: (any CameraMediaService)? = nil) {
        let key = mediaCameraID
        if mediaLibrary != nil, mediaLibraryKey == key {
            if mediaLibraryServiceID != service?.sessionID {
                mediaLibraryServiceID = service?.sessionID; mediaLibrary.bind(service)
            }
            return
        }
        mediaLibrary?.close(); retirePlaybackTransfers()
        let cameraMedia = cameraMedia
        let codec = LunaMediaCatalogCodec(source: backend, shotColor: { file in
            cameraMedia.shotColor(for: file.path, cameraID: key)
        })
        let preferences = MonitorMediaPreferences(storage: UserDefaults.standard,
            favoriteKey: "opc.media.fav.\(key)", lastCameraKey: "opc.media.lastCameraID")
        let cache = MonitorMediaCache(directory: cameraMedia.directory(cameraID: key), codec: codec,
            eligibility: .minimumFraction(numerator: 9, denominator: 10), catalogAddress: "index.json",
            preservedMetadata: ["index.json", "color.json"])
        mediaLibraryKey = key; mediaLibraryServiceID = service?.sessionID
        mediaLibrary = MonitorMediaLibraryModel(cache: cache, favorites: preferences, service: service)
    }
    func beginMediaBrowse() { mediaLibrary.begin() }
    func endMediaBrowse() { mediaLibrary.close() }
    func refreshMedia() { mediaLibrary.refresh() }
    func refreshMediaAfterCapture() async {
        if mediaLibrary.browsing, !mediaLibrary.fetching { mediaLibrary.refresh() }
    }
    var mediaFiles: [MediaFile] { mediaLibrary.records.map { record in
        var file = record.payload.file; file.isStarred = record.favorite; return file
    } }
    var mediaFetchInProgress: Bool { mediaLibrary.fetching }
    var mediaFetchListedCount: Int { mediaLibrary.fetchedCount }
    var mediaNote: String? { playbackMediaNote ?? mediaLibrary.note }
    var isBrowsingMedia: Bool { mediaLibrary.browsing }
    var mediaCacheRevision: UInt64 { mediaLibrary.cacheRevision }
    var mediaDownloadProgress: [String: Double] {
        var values: [String: Double] = [:]
        for record in mediaLibrary.records {
            if let value = mediaLibrary.progress[record.asset.id] { values[record.payload.file.path] = value }
        }
        return values
    }
    func mediaRecord(for file: MediaFile) -> MonitorMediaRecord<LunaMediaLibraryPayload>? {
        var content = file; content.isStarred = false
        return mediaLibrary.records.first { record in
            var candidate = record.payload.file; candidate.isStarred = false; return content == candidate
        }
    }
    static func mediaFile(_ luna: LunaMediaFile) -> MediaFile {
        let meta = luna.metadata
        let resolution: String? = {
            guard let w = meta?.width, let h = meta?.height, w > 0, h > 0 else { return nil }
            return "\(w)x\(h)"
        }()
        var duration = 0
        if let ms = meta?.durationMilliseconds {
            duration = Int((ms + 500) / 1000)
        } else if let seconds = meta?.durationSeconds {
            duration = Int(seconds)
        }
        let fps: Int? = meta?.frameRate.map { Int($0) }
        let size: UInt64 = meta?.fileSize ?? 0
        return MediaFile(
            path: luna.uri,
            thumbPath: luna.uri,
            // Preserve the legacy index handle. Admission comes from the typed source asset/service.
            handle: 1,
            sizeBytes: size,
            durationSeconds: duration,
            resolution: resolution,
            fps: fps,
            proxyPath: luna.isVideo ? luna.proxyURI : nil,
            storage: 0)
    }

    func ensureThumbnail(for file: MediaFile) async {
        if let id = mediaRecord(for: file)?.asset.id { await mediaLibrary.ensureThumbnailAndWait(id) }
    }
    func download(file: MediaFile) async {
        guard let id = mediaRecord(for: file)?.asset.id else { return }
        do { _ = try await mediaLibrary.cacheOriginal(id) }
        catch { playbackMediaNote = MediaOperatorCopy.downloadFailed }
    }
    func localURL(for file: MediaFile) -> URL? { CameraMedia.existingFile(cameraMedia.fileCacheURL(cameraID: mediaCameraID, file: file)) }
    func thumbnailURL(for file: MediaFile) -> URL? { CameraMedia.existingFile(cameraMedia.thumbnailCacheURL(cameraID: mediaCameraID, file: file)) }
    func isDownloaded(_ file: MediaFile) -> Bool {
        if let record = mediaRecord(for: file) { return mediaLibrary.cache.entry(record).originalURL != nil }
        guard let url = localURL(for: file) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64(max(0, $0)) } ?? 0
        return mediaLibrary.cache.eligibility.accepts(bytes: size, expected: file.sizeBytes > 0 ? file.sizeBytes : nil)
    }
    func cacheGrade(for file: MediaFile) -> MediaCacheGrade {
        .resolve(hasOriginal: isDownloaded(file), hasProxy: localProxySource(for: file) != nil)
    }
    func shotColor(for file: MediaFile) -> ColorMode? { cameraMedia.shotColor(for: file.path, cameraID: mediaCameraID) }
    func rememberShotColor(_ color: ColorMode, for file: MediaFile) { cameraMedia.rememberShotColor(color, path: file.path, cameraID: mediaCameraID) }
    func remotePlaybackURL(for file: MediaFile) -> URL? {
        MediaHTTP.previewPaths(file).lazy.compactMap { MediaHTTP.pathURL(storage: 0, path: $0, route: self.profile.media) }.first
    }
    func localProxySource(for file: MediaFile) -> MediaPlaybackSource? {
        for path in MediaHTTP.proxyPaths(file) {
            if let existing = CameraMedia.existingFile(cameraMedia.playbackCacheURL(cameraID: mediaCameraID, file: file, path: path)) {
                return .init(url: existing, mimeType: MediaHTTP.playbackMIMEType(for: path), isRemote: false, path: path)
            }
        }
        return nil
    }
    func localPlaybackSource(for file: MediaFile) -> MediaPlaybackSource? {
        if let proxy = localProxySource(for: file) { return proxy }
        if isDownloaded(file), let local = localURL(for: file) {
            return .init(url: local, mimeType: MediaHTTP.playbackMIMEType(for: file.path), isRemote: false, path: file.path)
        }
        return nil
    }
    func isAvailableOffline(_ file: MediaFile) -> Bool { localPlaybackSource(for: file) != nil }
    var canReachCameraMedia: Bool {
        guard case .live = phase else { return false }; return backend.isControlReady
    }
    func retirePlaybackTransfers() { playbackMediaNote = nil }
    func deleteMediaFiles(_ files: [MediaFile]) async {
        let ids = files.compactMap { mediaRecord(for: $0)?.asset.id }
        do { _ = try await mediaLibrary.delete(ids) } catch { playbackMediaNote = MediaOperatorCopy.deleteFailed }
    }
    func deleteMedia(_ file: MediaFile) async { await deleteMediaFiles([file]) }
    func toggleMediaFavorite(_ file: MediaFile) { if let id = mediaRecord(for: file)?.asset.id { mediaLibrary.toggleFavorite(id) } }
    func isMediaFavorite(_ file: MediaFile) -> Bool { mediaRecord(for: file)?.favorite ?? file.isStarred }
    func isFavorite(_ file: MediaFile) -> Bool { isMediaFavorite(file) }
    func toggleFavorite(_ file: MediaFile) { toggleMediaFavorite(file) }
    func resetMediaSession() {
        retirePlaybackTransfers(); mediaLibrary.close(); mediaLibraryServiceID = nil; mediaLibrary.bind(nil)
    }
    func clearMediaCache() async throws { retirePlaybackTransfers(); try await mediaLibrary.clearCache() }
    var mediaCameraID: String {
        let key = "opc.media.lastCameraID"
        if let id = connectedCamera?.id.uuidString {
            if UserDefaults.standard.string(forKey: key) != id { UserDefaults.standard.set(id, forKey: key) }; return id
        }
        return UserDefaults.standard.string(forKey: key) ?? "unknown"
    }
}

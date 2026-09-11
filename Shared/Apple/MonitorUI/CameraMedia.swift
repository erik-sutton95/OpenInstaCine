import CryptoKit
import Foundation
import MonitorContracts
import OpenPocketViewCore
import UniformTypeIdentifiers

/// Operator-facing media notes. Never name a sister app or another camera brand.
enum MediaOperatorCopy {
    static let listing = "Listing camera clips…"
    static let notConnected = "Connect the camera to list clips."
    static let playbackFailed = "Camera did not enter playback."
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

/// Shared local media cache, catalog and generic HTTP transfer support.
@MainActor
final class CameraMedia {
    var browseTask: Task<Void, Never>?
    var resumeLiveTask: Task<Void, Never>?
    var browseID = 0
    var resumeID = 0
    var playbackHeld = false
    var actionCounter: UInt32 = 1
    var favorites: Set<String> = []
    var favoritesCameraID: String?
    var thumbInFlight: Set<String> = []
    var downloadInFlight: Set<String> = []

    private let pump = MediaDownloadPump()
    private lazy var http: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
    private lazy var downloadHTTP: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 600
        return URLSession(configuration: cfg, delegate: pump, delegateQueue: nil)
    }()

    func nextBrowseID() -> Int {
        browseID += 1
        return browseID
    }

    func nextResumeID() -> Int {
        resumeID += 1
        return resumeID
    }

    func cancelResumeLive() {
        resumeLiveTask?.cancel()
        resumeLiveTask = nil
        resumeID += 1
    }

    func nextActionCounter() -> UInt32 {
        let value = actionCounter
        actionCounter &+= 1
        if actionCounter == 0 { actionCounter = 1 }
        return value
    }

    func loadFavorites(cameraID: String) -> Set<String> {
        if favoritesCameraID == cameraID { return favorites }
        favoritesCameraID = cameraID
        favorites = Set(
            UserDefaults.standard.stringArray(forKey: Self.favoritesKey(cameraID)) ?? [])
        return favorites
    }

    func persistFavorites() {
        guard let cameraID = favoritesCameraID else { return }
        UserDefaults.standard.set(Array(favorites).sorted(), forKey: Self.favoritesKey(cameraID))
    }

    func resetSession() {
        browseTask?.cancel()
        browseTask = nil
        cancelResumeLive()
        playbackHeld = false
        thumbInFlight.removeAll()
        downloadInFlight.removeAll()
        pump.cancelAll()
    }

    func cacheRoot(cameraID: String) -> URL {
        let app = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
            0]
        return app.appendingPathComponent("MonitorEngine/media/\(cameraID)", isDirectory: true)
    }

    func thumbnailCacheURL(cameraID: String, file: MediaFile) -> URL {
        cacheRoot(cameraID: cameraID)
            .appendingPathComponent("thumbs", isDirectory: true)
            .appendingPathComponent(Self.cacheName(file.thumbPath) + ".jpg")
    }

    func fileCacheURL(cameraID: String, file: MediaFile) -> URL {
        cacheRoot(cameraID: cameraID)
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(Self.cacheName(file.path))
    }

    /// Local copy used only for playback. Originals share the download cache so a
    /// play-to-open of the full file counts as downloaded.
    func playbackCacheURL(cameraID: String, file: MediaFile, path: String) -> URL {
        if path == file.path { return fileCacheURL(cameraID: cameraID, file: file) }
        return cacheRoot(cameraID: cameraID)
            .appendingPathComponent("play", isDirectory: true)
            .appendingPathComponent(Self.cacheName(path))
    }

    func getData(url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await http.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw MediaTransferError.badResponse }
        return (data, http)
    }

    /// Last 2 MiB of the original take — LRF Keys are Rec.709 even for log.
    func getRange(url: URL, range: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue(range, forHTTPHeaderField: "Range")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, response) = try await http.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MediaTransferError.badResponse }
        return (data, http)
    }

    /// Existence check that does not pull the body. HEAD first; ranged GET if the
    /// camera rejects HEAD. Cancels as soon as the status line is in.
    func probeExists(url: URL) async -> Bool {
        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        head.timeoutInterval = 4
        if let (_, response) = try? await http.data(for: head),
            let http = response as? HTTPURLResponse
        {
            if (200...299).contains(http.statusCode) { return true }
            if http.statusCode == 404 || http.statusCode == 400 { return false }
        }
        var get = URLRequest(url: url)
        get.httpMethod = "GET"
        get.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        get.timeoutInterval = 4
        do {
            let (bytes, response) = try await http.bytes(for: get)
            bytes.task.cancel()
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func downloadFile(
        from url: URL,
        to dest: URL,
        path: String,
        expectedSize: UInt64 = 0,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await pump.download(
            session: downloadHTTP, from: url, to: dest, path: path, expectedSize: expectedSize,
            onProgress: onProgress)
    }

    func catalogURL(cameraID: String) -> URL {
        cacheRoot(cameraID: cameraID).appendingPathComponent("index.json")
    }

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
        let url = colorStoreURL(cameraID: cameraID)
        guard let data = try? Data(contentsOf: url),
            let map = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return map
    }

    private func persistColorMap(_ map: [String: Int], cameraID: String) {
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
        let legacyKey = "MonitorEngine.ClipShotColor"
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

    func persistCatalog(_ files: [MediaFile], cameraID: String) {
        let url = catalogURL(cameraID: cameraID)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(files).write(to: url, options: .atomic)
        } catch {
            ControlLiveLog.line("media: catalog write failed \(error.localizedDescription)")
        }
    }

    func loadCatalog(cameraID: String) -> [MediaFile] {
        let url = catalogURL(cameraID: cameraID)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MediaFile].self, from: data)) ?? []
    }

    func cacheByteCount(cameraID: String) -> UInt64 {
        let root = cacheRoot(cameraID: cameraID)
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
        else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            total += UInt64(values?.fileSize ?? 0)
        }
        return total
    }

    func clearCache(cameraID: String, preservingCatalog: Bool) {
        pump.cancelAll()
        let root = cacheRoot(cameraID: cameraID)
        let catalog = preservingCatalog ? loadCatalog(cameraID: cameraID) : []
        try? FileManager.default.removeItem(at: root)
        if preservingCatalog, !catalog.isEmpty {
            persistCatalog(catalog, cameraID: cameraID)
        }
    }

    func writeAtomically(_ data: Data, to dest: URL) throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".part")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    static func existingFile(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
            !isDir.boolValue
        else { return nil }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size]
            as? NSNumber,
            size.intValue <= 0
        {
            return nil
        }
        return url
    }

    private static func favoritesKey(_ cameraID: String) -> String {
        "monitor.media.fav.\(cameraID)"
    }

    static func mimeType(for path: String) -> String {
        UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }
    private static func cacheName(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        let ext = (path as NSString).pathExtension.lowercased()
        return ext.isEmpty ? digest : digest + "." + ext
    }
}

enum MediaTransferError: Error {
    case badResponse
    case httpStatus(Int)
    case timeout
}

struct MediaPlaybackSource: Equatable {
    var url: URL
    var mimeType: String
    var isRemote: Bool
    var path: String
}

/// Streams bodies to disk and completes at the declared content length.
private final class MediaDownloadPump: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Job {
        var dest: URL
        var tmp: URL
        var handle: FileHandle?
        var expected: UInt64
        var written: UInt64 = 0
        var onProgress: @MainActor @Sendable (Double) -> Void
        var continuation: CheckedContinuation<Void, Error>
        var finished = false
        var status: Int = 0
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]

    func download(
        session: URLSession,
        from url: URL,
        to dest: URL,
        path: String,
        expectedSize: UInt64,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        _ = path
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let tmp = dest.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString + ".part")
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            let handle = try? FileHandle(forWritingTo: tmp)
            let task = session.dataTask(with: request)
            lock.lock()
            jobs[task.taskIdentifier] = Job(
                dest: dest,
                tmp: tmp,
                handle: handle,
                expected: expectedSize,
                onProgress: onProgress,
                continuation: cont)
            lock.unlock()
            task.resume()
        }
    }

    func cancelAll() {
        lock.lock()
        let pending = jobs
        jobs.removeAll()
        lock.unlock()
        for job in pending.values {
            try? job.handle?.close()
            try? FileManager.default.removeItem(at: job.tmp)
            if !job.finished {
                job.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let length = max(0, response.expectedContentLength)
        lock.lock()
        if var job = jobs[dataTask.taskIdentifier] {
            job.status = status
            if length > 0 { job.expected = UInt64(length) }
            jobs[dataTask.taskIdentifier] = job
        }
        lock.unlock()
        if status != 0, !(200...299).contains(status) {
            completionHandler(.cancel)
            finish(task: dataTask, error: MediaTransferError.httpStatus(status))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard var job = jobs[dataTask.taskIdentifier], !job.finished else {
            lock.unlock()
            return
        }
        do {
            try job.handle?.write(contentsOf: data)
            job.written += UInt64(data.count)
            jobs[dataTask.taskIdentifier] = job
            let written = job.written
            let expected = job.expected
            let progress = expected > 0 ? min(1, Double(written) / Double(expected)) : 0
            let onProgress = job.onProgress
            let complete = expected > 0 && written >= expected
            lock.unlock()
            Task { @MainActor in onProgress(progress) }
            if complete {
                dataTask.cancel()
                finish(task: dataTask, error: nil)
            }
        } catch {
            lock.unlock()
            finish(task: dataTask, error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        if let error, (error as NSError).code == NSURLErrorCancelled {
            lock.lock()
            let already = jobs[task.taskIdentifier]?.finished ?? true
            lock.unlock()
            if already { return }
        }
        finish(task: task, error: error)
    }

    private func finish(task: URLSessionTask, error: Error?) {
        lock.lock()
        guard var job = jobs[task.taskIdentifier], !job.finished else {
            lock.unlock()
            return
        }
        job.finished = true
        jobs[task.taskIdentifier] = job
        lock.unlock()

        try? job.handle?.close()

        if let error, (error as NSError).code != NSURLErrorCancelled {
            try? FileManager.default.removeItem(at: job.tmp)
            job.continuation.resume(throwing: error)
            lock.lock()
            jobs[task.taskIdentifier] = nil
            lock.unlock()
            return
        }

        do {
            guard job.written > 0, FileManager.default.fileExists(atPath: job.tmp.path) else {
                throw MediaTransferError.badResponse
            }
            if FileManager.default.fileExists(atPath: job.dest.path) {
                try FileManager.default.removeItem(at: job.dest)
            }
            try FileManager.default.moveItem(at: job.tmp, to: job.dest)
            lock.lock()
            jobs[task.taskIdentifier] = nil
            lock.unlock()
            job.continuation.resume()
        } catch {
            try? FileManager.default.removeItem(at: job.tmp)
            lock.lock()
            jobs[task.taskIdentifier] = nil
            lock.unlock()
            job.continuation.resume(throwing: error)
        }
    }
}

extension CameraSession {
    var mediaCameraID: String {
        connectedCamera?.id.uuidString ?? UserDefaults.standard.string(
            forKey: "MonitorEngine.lastMediaCamera") ?? "local"
    }
    func beginMediaBrowse() {
        isBrowsingMedia = true
        loadMediaFavorites()
        loadCachedCatalogIfNeeded()
        refreshMedia()
    }
    func endMediaBrowse() { isBrowsingMedia = false }
    /// Opening the library does not change the camera feed's transport lifetime.
    func refreshMedia() {
        cameraMedia.browseTask?.cancel()
        cameraMedia.browseTask = Task { [weak self] in await self?.refreshMedia() }
    }
    func refreshMedia() async {
        guard canReachCameraMedia else {
            mediaFetchInProgress = false
            mediaFetchListedCount = mediaFiles.count
            mediaNote =
                capabilities.contains(.cameraMedia)
                ? MediaOperatorCopy.notConnected
                : "Camera media access is not connected for this camera yet. Cached clips remain available."
            return
        }
        let token = generation
        let cameraID = mediaCameraID
        mediaFetchInProgress = true
        mediaNote = MediaOperatorCopy.listing
        defer { if token == generation, cameraID == mediaCameraID { mediaFetchInProgress = false } }
        do {
            let assets = try await backend.listMedia()
            try validateMediaContext(generation: token, cameraID: cameraID)
            var mapped: [String: CameraMediaAsset] = [:]
            let files = assets.map { asset -> MediaFile in
                // Cache paths are local logical identifiers. An adapter sees its original opaque
                // asset ID, never these presentation handles or legacy file-path conventions.
                let digest = SHA256.hash(data: Data(asset.id.utf8)).map {
                    String(format: "%02x", $0)
                }.joined()
                let name = (asset.filename as NSString).lastPathComponent
                let path = "assets/\(digest)/\(name)"
                mapped[path] = asset
                return MediaFile(
                    path: path, thumbPath: path + ".thumbnail.jpg",
                    handle: asset.canDelete ? 1 : 0, sizeBytes: asset.bytes ?? 0,
                    durationSeconds: Int(asset.durationSeconds ?? 0),
                    isStarred: mediaLocalFavorites.contains(path), resolution: asset.resolution,
                    fps: asset.framesPerSecond.map(Int.init))
            }
            mediaAssets = mapped
            mediaFiles = files
            mediaFetchListedCount = files.count
            mediaNote = files.isEmpty ? MediaOperatorCopy.noClips : nil
            persistMediaCatalog()
            persistAssetCatalog()
        } catch {
            if !Task.isCancelled, token == generation, cameraID == mediaCameraID {
                mediaNote = error.localizedDescription
            }
        }
    }
    func ensureThumbnail(for file: MediaFile) async {
        guard canReachCameraMedia, thumbnailURL(for: file) == nil,
            let asset = mediaAssets[file.path], cameraMedia.thumbInFlight.insert(file.path).inserted
        else { return }
        let token = generation
        let cameraID = mediaCameraID
        defer {
            if token == generation, cameraID == mediaCameraID {
                cameraMedia.thumbInFlight.remove(file.path)
            }
        }
        let destination = cameraMedia.thumbnailCacheURL(cameraID: mediaCameraID, file: file)
        do {
            try await fetch(
                asset, representation: .thumbnail, destination: destination, progress: { _ in })
        } catch {
            if !Task.isCancelled, token == generation, cameraID == mediaCameraID {
                mediaNote = MediaOperatorCopy.thumbFailed
            }
        }
    }
    func download(file: MediaFile) async {
        guard !isDownloaded(file) else { return }
        guard canReachCameraMedia, let asset = mediaAssets[file.path] else {
            mediaNote = MediaOperatorCopy.clipNotCached
            return
        }
        guard cameraMedia.downloadInFlight.insert(file.path).inserted else { return }
        let token = generation
        let cameraID = mediaCameraID
        defer {
            if token == generation, cameraID == mediaCameraID {
                cameraMedia.downloadInFlight.remove(file.path)
                mediaDownloadProgress[file.path] = nil
            }
        }
        let destination = cameraMedia.fileCacheURL(cameraID: mediaCameraID, file: file)
        mediaDownloadProgress[file.path] = 0
        do {
            try await fetch(asset, representation: .original, destination: destination) {
                [weak self] value in
                guard let self, self.generation == token, self.mediaCameraID == cameraID else {
                    return
                }
                self.mediaDownloadProgress[file.path] = value
            }
        } catch {
            if !Task.isCancelled, token == generation, cameraID == mediaCameraID {
                mediaNote = error.localizedDescription
            }
        }
    }
    private func fetch(
        _ asset: CameraMediaAsset, representation: CameraMediaRepresentation,
        destination: URL, progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        let token = generation
        let cameraID = mediaCameraID
        try validateMediaContext(generation: token, cameraID: cameraID)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            UUID().uuidString + ".part")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await backend.downloadMedia(
            asset, representation: representation, to: temporary, progress: progress)
        try validateMediaContext(generation: token, cameraID: cameraID)
        guard CameraMedia.existingFile(temporary) != nil else {
            throw MediaTransferError.badResponse
        }
        if representation == .original, let bytes = asset.bytes, bytes > 0 {
            let actual =
                ((try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size])
                as? NSNumber)?.uint64Value ?? 0
            guard actual == bytes else { throw MediaTransferError.badResponse }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
    func localURL(for file: MediaFile) -> URL? {
        CameraMedia.existingFile(cameraMedia.fileCacheURL(cameraID: mediaCameraID, file: file))
    }
    func fetchOriginalShotColor(for file: MediaFile) async -> ColorMode? {
        if let url = localURL(for: file),
            let color = ClipColorProfileIO.shotColor(at: url, path: file.path)
        {
            rememberShotColor(color, for: file)
            return color
        }
        return shotColor(for: file)
    }
    func shotColor(for file: MediaFile) -> ColorMode? {
        cameraMedia.shotColor(for: file.path, cameraID: mediaCameraID)
    }
    func rememberShotColor(_ color: ColorMode, for file: MediaFile) {
        cameraMedia.rememberShotColor(color, path: file.path, cameraID: mediaCameraID)
    }
    func cacheGrade(for file: MediaFile) -> MediaCacheGrade {
        MediaCacheGrade.resolve(
            hasOriginal: isDownloaded(file), hasProxy: localProxySource(for: file) != nil)
    }
    func thumbnailURL(for file: MediaFile) -> URL? {
        CameraMedia.existingFile(cameraMedia.thumbnailCacheURL(cameraID: mediaCameraID, file: file))
    }
    func isDownloaded(_ file: MediaFile) -> Bool {
        guard let url = localURL(for: file) else { return false }
        guard file.sizeBytes > 0 else { return true }
        let size =
            ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?
            .uint64Value ?? 0
        return size >= file.sizeBytes
    }
    func localPlaybackSource(for file: MediaFile) -> MediaPlaybackSource? {
        if let proxy = localProxySource(for: file) { return proxy }
        guard isDownloaded(file), let url = localURL(for: file) else { return nil }
        return MediaPlaybackSource(
            url: url, mimeType: CameraMedia.mimeType(for: file.path), isRemote: false,
            path: file.path)
    }
    func localProxySource(for file: MediaFile) -> MediaPlaybackSource? {
        for path in file.proxyPath.map({ [$0] }) ?? [] {
            let dest = cameraMedia.playbackCacheURL(cameraID: mediaCameraID, file: file, path: path)
            if let url = CameraMedia.existingFile(dest) {
                return MediaPlaybackSource(
                    url: url, mimeType: CameraMedia.mimeType(for: path), isRemote: false, path: path
                )
            }
        }
        return nil
    }
    func isAvailableOffline(_ file: MediaFile) -> Bool { localPlaybackSource(for: file) != nil }
    var canReachCameraMedia: Bool { capabilities.contains(.cameraMedia) && phase == .live }
    func resolvePlaybackSource(for file: MediaFile) async -> MediaPlaybackSource? {
        localPlaybackSource(for: file)
    }
    func remainingPlaybackSources(for file: MediaFile, after source: MediaPlaybackSource)
        -> [MediaPlaybackSource]
    {
        guard source.path != file.path, isDownloaded(file), let url = localURL(for: file) else {
            return []
        }
        return [
            MediaPlaybackSource(
                url: url, mimeType: CameraMedia.mimeType(for: file.path), isRemote: false,
                path: file.path)
        ]
    }
    func cachePlaybackFile(file: MediaFile, path: String) async throws -> URL {
        let dest = cameraMedia.playbackCacheURL(cameraID: mediaCameraID, file: file, path: path)
        if let url = CameraMedia.existingFile(dest) { return url }
        guard canReachCameraMedia, let asset = mediaAssets[file.path] else {
            throw MediaTransferError.badResponse
        }
        try await fetch(
            asset, representation: path == file.path ? .original : .proxy, destination: dest,
            progress: { _ in })
        return dest
    }
    func deleteMediaFiles(_ files: [MediaFile]) async {
        guard canReachCameraMedia else {
            mediaNote = "Deleting camera clips is not connected for this camera yet."
            return
        }
        let token = generation
        let cameraID = mediaCameraID
        for file in files {
            guard token == generation, cameraID == mediaCameraID, !Task.isCancelled else { return }
            guard let asset = mediaAssets[file.path], asset.canDelete else {
                mediaNote = MediaOperatorCopy.notDeletable
                continue
            }
            do {
                try validateMediaContext(generation: token, cameraID: cameraID)
                try await backend.deleteMedia(asset)
                try validateMediaContext(generation: token, cameraID: cameraID)
                mediaFiles.removeAll { $0.path == file.path }
                mediaAssets[file.path] = nil
                mediaLocalFavorites.remove(file.path)
                for url in [localURL(for: file), thumbnailURL(for: file)] {
                    if let url { try? FileManager.default.removeItem(at: url) }
                }
            } catch {
                guard token == generation, cameraID == mediaCameraID, !Task.isCancelled else {
                    return
                }
                mediaNote = error.localizedDescription
                break
            }
        }
        persistMediaCatalog()
        persistAssetCatalog()
    }
    func isFavorite(_ file: MediaFile) -> Bool {
        mediaLocalFavorites.contains(file.path) || file.isStarred
    }
    func toggleFavorite(_ file: MediaFile) {
        if isFavorite(file) {
            mediaLocalFavorites.remove(file.path)
        } else {
            mediaLocalFavorites.insert(file.path)
        }
        if let index = mediaFiles.firstIndex(where: { $0.path == file.path }) {
            mediaFiles[index].isStarred = mediaLocalFavorites.contains(file.path)
        }
        cameraMedia.favorites = mediaLocalFavorites
        cameraMedia.persistFavorites()
        persistMediaCatalog()
    }
    func persistMediaCatalog() { cameraMedia.persistCatalog(mediaFiles, cameraID: mediaCameraID) }
    func loadCachedCatalogIfNeeded() {
        if mediaFiles.isEmpty { mediaFiles = cameraMedia.loadCatalog(cameraID: mediaCameraID) }
        if mediaAssets.isEmpty, let data = try? Data(contentsOf: assetCatalogURL) {
            mediaAssets =
                (try? JSONDecoder().decode([String: CameraMediaAsset].self, from: data)) ?? [:]
        }
    }
    private func validateMediaContext(generation token: Int, cameraID: String) throws {
        try Task.checkCancellation()
        guard token == generation, cameraID == mediaCameraID else { throw CancellationError() }
    }
    private var assetCatalogURL: URL {
        cameraMedia.cacheRoot(cameraID: mediaCameraID).appendingPathComponent("assets.json")
    }
    private func persistAssetCatalog() {
        do {
            try cameraMedia.writeAtomically(JSONEncoder().encode(mediaAssets), to: assetCatalogURL)
        } catch { ControlLiveLog.line("media: asset catalog could not be saved") }
    }
    func loadMediaFavorites() {
        mediaLocalFavorites = cameraMedia.loadFavorites(cameraID: mediaCameraID)
    }
}

import Foundation
import OpenPocketViewCore
import Insta360Protocol

/// One bounded post-gallery owner. Dependencies are the actual shell operations;
/// tests drive this same loop without a camera or wall-clock-length deadline.
@MainActor
enum MediaLiveResumeRunner {
    enum Result: Equatable { case restored, exhausted, superseded }

    static func run(
        timeout: Duration = .seconds(FeedWatchdog.decoderRepairDeadline),
        isCurrent: () -> Bool,
        inPlayback: () -> Bool,
        pictureFresh: () -> Bool,
        exitPlayback: () async -> Bool,
        enableLiveView: () -> Bool
    ) async -> Result {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var attempt = 1
        var exitAcknowledged = false
        var enableSent = false
        while !Task.isCancelled, isCurrent() {
            switch MediaLiveResume.action(
                attempt: attempt, inPlayback: inPlayback(),
                exitAcknowledged: exitAcknowledged, pictureFresh: pictureFresh(),
                enableSent: enableSent, deadlineExpired: ContinuousClock.now >= deadline)
            {
            case .done:
                return .restored
            case .exhausted:
                return .exhausted
            case .exitPlayback:
                let acknowledged = await exitPlayback()
                exitAcknowledged = acknowledged || exitAcknowledged
                attempt += 1
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return .superseded }
            case .enableLiveView:
                enableSent = enableLiveView()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return .superseded }
            case .waitForPicture:
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return .superseded }
            }
        }
        return .superseded
    }
}

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

/// Playback-held media list + SoftAP HTTP cache. Owned by `CameraSession`.
@MainActor
final class CameraMedia {
    private let fileManager: FileManager
    private let httpConfiguration: URLSessionConfiguration

    private lazy var applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]

    init(
        fileManager: FileManager = .default,
        httpConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.fileManager = fileManager
        self.httpConfiguration = httpConfiguration
    }

    var assembler = MediaChunkAssembler()
    var browseTask: Task<Void, Never>?
    var resumeLiveTask: Task<Void, Never>?
    var browseID = 0
    var resumeID = 0
    var playbackHeld = false
    var actionCounter: UInt32 = 1
    var storageWinner: [String: Int] = [:]
    var favorites: Set<String> = []
    var favoritesCameraID: String?
    var thumbInFlight: Set<String> = []
    var downloadInFlight: Set<String> = []
    private var colorMapCache: (cameraID: String, map: [String: Int])?

    private let pump = MediaDownloadPump()
    private lazy var http: URLSession = {
        let cfg = httpConfiguration.copy() as! URLSessionConfiguration
        cfg.allowsCellularAccess = false
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
    private lazy var downloadHTTP: URLSession = {
        let cfg = httpConfiguration.copy() as! URLSessionConfiguration
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
        assembler.reset()
        storageWinner.removeAll()
        thumbInFlight.removeAll()
        downloadInFlight.removeAll()
        pump.cancelAll()
    }

    func cacheRoot(cameraID: String) -> URL {
        #if DEBUG && targetEnvironment(simulator)
            if MonitorMediaReview.isActive { return MonitorMediaReview.cacheRoot }
        #endif
        return applicationSupport.appendingPathComponent(
            "OpenInstaCine/media/\(cameraID)", isDirectory: true)
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
            .appendingPathComponent(MediaHTTP.playbackCacheFileName(path))
    }

    func resolvedStorage(for file: MediaFile, singleSd: Bool) -> Int {
        MediaHTTP.resolvedStorage(
            stamped: file.storage,
            handle: file.handle != 0 ? file.handle : file.cmdHandle,
            winner: storageWinner[file.path],
            singleSdStorage: singleSd)
    }

    func rememberStorage(_ storage: Int, for path: String) {
        storageWinner[path] = storage
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

    /// Snapshot disk state once per catalog/cache revision, away from SwiftUI body evaluation.
    func cacheEntries(cameraID: String, files: [MediaFile]) async -> [String: MediaCacheEntry] {
        let root = cacheRoot(cameraID: cameraID)
        let manager = fileManager
        let scan = Task.detached(priority: .utility) {
            var entries: [String: MediaCacheEntry] = [:]
            for file in files {
                if Task.isCancelled { break }
                let original = root.appendingPathComponent("files")
                    .appendingPathComponent(Self.cacheName(file.path))
                let attributes = try? manager.attributesOfItem(atPath: original.path)
                let bytes = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
                let isFile = attributes?[.type] as? FileAttributeType == .typeRegular
                let hasOriginal =
                    isFile && bytes > 0
                    && (file.sizeBytes == 0 || bytes >= file.sizeBytes * 9 / 10)
                let hasProxy = MediaHTTP.proxyPaths(file).contains { path in
                    let url = root.appendingPathComponent("play")
                        .appendingPathComponent(MediaHTTP.playbackCacheFileName(path))
                    return Self.existingFile(url, fileManager: manager) != nil
                }
                let thumb = root.appendingPathComponent("thumbs")
                    .appendingPathComponent(Self.cacheName(file.thumbPath) + ".jpg")
                entries[file.path] = MediaCacheEntry(
                    grade: .resolve(hasOriginal: hasOriginal, hasProxy: hasProxy),
                    originalURL: hasOriginal ? original : nil,
                    thumbnailURL: Self.existingFile(thumb, fileManager: manager))
            }
            return entries
        }
        return await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    func cacheByteCount(cameraID: String) async -> UInt64 {
        let root = cacheRoot(cameraID: cameraID)
        let manager = fileManager
        let scan = Task.detached(priority: .utility) {
            Self.cacheByteCount(at: root, fileManager: manager)
        }
        return await withTaskCancellationHandler {
            await scan.value
        } onCancel: {
            scan.cancel()
        }
    }

    private nonisolated static func retiredCaches(
        at root: URL, fileManager: FileManager, includeUnprepared: Bool = false
    ) -> [URL] {
        let siblings =
            (try? fileManager.contentsOfDirectory(
                at: root.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        return siblings.filter {
            $0.lastPathComponent.hasPrefix(".clearing-" + root.lastPathComponent + "-")
                || (includeUnprepared
                    && $0.lastPathComponent.hasPrefix(".retiring-" + root.lastPathComponent + "-"))
        }
    }

    private nonisolated static func cacheByteCount(at root: URL, fileManager: FileManager) -> UInt64
    {
        var total: UInt64 = 0
        // Failed deletions still occupy storage and must stay visible/retryable.
        for directory in [root]
            + retiredCaches(at: root, fileManager: fileManager, includeUnprepared: true)
        {
            guard
                let enumerator = fileManager.enumerator(
                    at: directory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
            else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return total }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true { continue }
                total += UInt64(max(0, values?.fileSize ?? 0))
            }
        }
        return total
    }

    func clearCache(cameraID: String, preservingCatalog: Bool) async throws {
        pump.cancelAll()
        let root = cacheRoot(cameraID: cameraID)
        if fileManager.fileExists(atPath: root.path) {
            // Retire the directory before yielding. Recursive deletion must never
            // target the live path, where a later download can create new files.
            let suffix = root.lastPathComponent + "-" + UUID().uuidString
            let retired = root.deletingLastPathComponent().appendingPathComponent(
                ".retiring-" + suffix, isDirectory: true)
            let ready = root.deletingLastPathComponent().appendingPathComponent(
                ".clearing-" + suffix, isDirectory: true)
            try fileManager.moveItem(at: root, to: retired)
            var preserved: [String] = []
            do {
                if preservingCatalog {
                    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                    for name in ["index.json", "color.json"] {
                        let source = retired.appendingPathComponent(name)
                        if fileManager.fileExists(atPath: source.path) {
                            try fileManager.moveItem(
                                at: source, to: root.appendingPathComponent(name))
                            preserved.append(name)
                        }
                    }
                }
                // Only a fully prepared tree is eligible for a deletion sweep.
                // Another Clear may already be deleting its own retired files.
                try fileManager.moveItem(at: retired, to: ready)
            } catch {
                // Restore metadata and the original directory if preparation
                // fails. If rollback itself fails, keep both trees for inspection.
                try? restoreRetiredCache(retired, to: root, preserved: preserved)
                throw error
            }
        }
        let manager = fileManager
        try await Task.detached(priority: .utility) {
            for retired in Self.retiredCaches(at: root, fileManager: manager) {
                try manager.removeItem(at: retired)
            }
        }.value
    }

    private func restoreRetiredCache(_ retired: URL, to root: URL, preserved: [String]) throws {
        for name in preserved.reversed() {
            try fileManager.moveItem(
                at: root.appendingPathComponent(name), to: retired.appendingPathComponent(name))
        }
        if fileManager.fileExists(atPath: root.path) {
            // Never recursively delete files a transfer may have created.
            guard try fileManager.contentsOfDirectory(atPath: root.path).isEmpty else { return }
            try fileManager.removeItem(at: root)
        }
        try fileManager.moveItem(at: retired, to: root)
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

    private static func favoritesKey(_ cameraID: String) -> String {
        "opc.media.fav.\(cameraID)"
    }

    private nonisolated static func cacheName(_ path: String) -> String {
        path.replacingOccurrences(of: "/", with: "_")
    }
}

struct MediaCacheEntry: Sendable {
    var grade: MediaCacheGrade
    var originalURL: URL?
    var thumbnailURL: URL?
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

/// Streams `/v2` bodies to disk. A download-task wait-for-EOF hangs at 100% on
/// Pocket SoftAP (the camera often keeps the socket open after Content-Length).
final class MediaDownloadPump: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var task: URLSessionDataTask?

        func install(_ task: URLSessionDataTask) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            self.task = task
            return cancelled
        }

        func cancel() -> URLSessionDataTask? {
            lock.lock()
            defer { lock.unlock() }
            cancelled = true
            return task
        }
    }

    private struct Job {
        var task: URLSessionDataTask
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
        let cancellation = Cancellation()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let tmp = dest.deletingLastPathComponent()
                    .appendingPathComponent(UUID().uuidString + ".part")
                FileManager.default.createFile(atPath: tmp.path, contents: nil)
                let handle = try? FileHandle(forWritingTo: tmp)
                let task = session.dataTask(with: request)
                lock.lock()
                jobs[task.taskIdentifier] = Job(
                    task: task,
                    dest: dest,
                    tmp: tmp,
                    handle: handle,
                    expected: expectedSize,
                    onProgress: onProgress,
                    continuation: cont)
                lock.unlock()
                // Install only after registering the continuation. A cancellation
                // before installation is remembered; one after it removes the job.
                if cancellation.install(task) {
                    cancel(task: task)
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            if let task = cancellation.cancel() { self.cancel(task: task) }
        }
        try Task.checkCancellation()
    }

    private func cancel(task: URLSessionDataTask) {
        lock.lock()
        let job = jobs[task.taskIdentifier]
        if job?.finished == false { jobs[task.taskIdentifier] = nil }
        lock.unlock()
        task.cancel()
        guard let job, !job.finished else { return }
        try? job.handle?.close()
        try? FileManager.default.removeItem(at: job.tmp)
        job.continuation.resume(throwing: CancellationError())
    }

    func cancelAll() {
        lock.lock()
        let pending = jobs
        jobs.removeAll()
        lock.unlock()
        for job in pending.values {
            job.task.cancel()
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
            let taskID = dataTask.taskIdentifier
            let complete = expected > 0 && written >= expected
            lock.unlock()
            Task { @MainActor [weak self] in self?.publishProgress(progress, taskID: taskID) }
            if complete {
                dataTask.cancel()
                finish(task: dataTask, error: nil)
            }
        } catch {
            lock.unlock()
            finish(task: dataTask, error: error)
        }
    }

    @MainActor private func publishProgress(_ progress: Double, taskID: Int) {
        // Cancellation/completion may retire the transfer before this queued
        // publication runs. Never recreate the cleared progress entry afterward.
        lock.lock()
        let job = jobs[taskID]
        lock.unlock()
        guard let job, !job.finished else { return }
        job.onProgress(progress)
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


// MARK: - Luna media (UCD2 list/thumbnail/delete + HTTP on 192.168.42.1)

extension CameraSession {
    func beginMediaBrowse() {
        cameraMedia.browseTask?.cancel()
        loadMediaFavorites()
        loadCachedCatalogIfNeeded()
        guard canReachCameraMedia else {
            isBrowsingMedia = true
            mediaFetchInProgress = false
            mediaNote = mediaFiles.isEmpty ? MediaOperatorCopy.notConnected : nil
            return
        }
        isBrowsingMedia = true
        mediaFetchInProgress = true
        mediaFetchListedCount = mediaFiles.count
        mediaNote = MediaOperatorCopy.listing
        let id = cameraMedia.nextBrowseID()
        cameraMedia.browseTask = Task { [weak self] in
            // The official app stops the preview while its album is open; HTTP then
            // has the Wi-Fi link to itself.
            await self?.backend.pauseLive()
            await self?.listLunaMedia(id: id)
        }
    }

    func endMediaBrowse() {
        cameraMedia.browseTask?.cancel()
        cameraMedia.browseTask = nil
        cameraMedia.browseID += 1
        mediaFetchInProgress = false
        let wasBrowsing = isBrowsingMedia
        isBrowsingMedia = false
        mediaNote = nil
        guard wasBrowsing, backend.isControlReady else { return }
        decoder.flushForRecovery()
        Task { [weak self] in
            try? await self?.backend.restartLive()
        }
    }

    func refreshMedia() {
        Task { await self.refreshMedia() }
    }

    func refreshMedia() async {
        loadMediaFavorites()
        guard canReachCameraMedia else {
            mediaNote = MediaOperatorCopy.notConnected
            return
        }
        if !isBrowsingMedia {
            beginMediaBrowse()
            return
        }
        if mediaFetchInProgress { return }
        mediaFetchInProgress = true
        mediaNote = MediaOperatorCopy.listing
        await listLunaMedia(id: cameraMedia.nextBrowseID())
    }

    /// A new clip or photo landed: re-list only while the library is open.
    func refreshMediaAfterCapture() async {
        guard isBrowsingMedia, !mediaFetchInProgress else { return }
        mediaFetchInProgress = true
        await listLunaMedia(id: cameraMedia.nextBrowseID())
    }

    private func listLunaMedia(id: Int) async {
        defer { if id == cameraMedia.browseID { mediaFetchInProgress = false } }
        do {
            let files = try await backend.listFiles()
            guard id == cameraMedia.browseID, !Task.isCancelled else { return }
            lunaFiles = Dictionary(files.map { ($0.uri, $0) }, uniquingKeysWith: { a, _ in a })
            let mapped = files.map(Self.mediaFile).map(applyFavoriteOverlay)
                .sorted { ($0.filenameTimestamp ?? "") > ($1.filenameTimestamp ?? "") }
            publishMediaFiles(mapped)
            mediaNote = mapped.isEmpty ? MediaOperatorCopy.noClips : nil
        } catch {
            guard id == cameraMedia.browseID else { return }
            ControlLiveLog.line("media: list failed \(error.localizedDescription)")
            mediaNote = MediaOperatorCopy.listFailed
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
            // Non-zero handle: Luna deletes by URI, so every listed file is deletable.
            handle: 1,
            sizeBytes: size,
            durationSeconds: duration,
            resolution: resolution,
            fps: fps,
            proxyPath: luna.isVideo ? luna.proxyURI : nil,
            storage: 0)
    }

    func ensureThumbnail(for file: MediaFile) async {
        guard thumbnailURL(for: file) == nil else { return }
        guard canReachCameraMedia else { return }
        guard cameraMedia.thumbInFlight.insert(file.path).inserted else { return }
        defer { cameraMedia.thumbInFlight.remove(file.path) }
        do {
            let thumb = try await backend.thumbnail(uri: file.path)
            guard let jpeg = LunaThumbnailImage.jpeg(thumb) else {
                throw MediaTransferError.badResponse
            }
            try cameraMedia.writeAtomically(jpeg, to: mediaThumbDest(file))
            mediaCacheRevision &+= 1
        } catch {
            ControlLiveLog.line("media: thumbnail failed \(file.filename) \(error.localizedDescription)")
            if mediaNote == nil { mediaNote = MediaOperatorCopy.thumbFailed }
        }
    }

    func download(file: MediaFile) async {
        if isDownloaded(file) {
            finishDownloadProgress(file.path)
            return
        }
        guard canReachCameraMedia else {
            mediaNote = MediaOperatorCopy.clipNotCached
            return
        }
        guard cameraMedia.downloadInFlight.insert(file.path).inserted else { return }
        defer { cameraMedia.downloadInFlight.remove(file.path) }
        mediaDownloadProgress[file.path] = 0
        let dest = mediaFileDest(file)
        do {
            try await fetchMediaFile(file: file, path: file.path, to: dest)
            guard CameraMedia.existingFile(dest) != nil else { throw MediaTransferError.badResponse }
            finishDownloadProgress(file.path)
        } catch {
            mediaDownloadProgress[file.path] = nil
            mediaNote = MediaOperatorCopy.downloadFailed
            ControlLiveLog.line("media: download failed \(file.filename) \(error.localizedDescription)")
        }
    }

    private func finishDownloadProgress(_ path: String) {
        mediaCacheRevision &+= 1
        mediaDownloadProgress[path] = 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            if mediaDownloadProgress[path] == 1 { mediaDownloadProgress[path] = nil }
        }
    }

    func localURL(for file: MediaFile) -> URL? {
        CameraMedia.existingFile(mediaFileDest(file))
    }

    /// Shot color from the camera's clip metadata (I-Log / Standard / Dolby).
    func fetchOriginalShotColor(for file: MediaFile) async -> ColorMode? {
        if let cached = shotColor(for: file) { return cached }
        guard let gamma = lunaFiles[file.path]?.metadata?.gammaMode?.lowercased() else { return nil }
        let mode: ColorMode?
        if gamma.contains("log") {
            mode = .iLog
        } else if gamma.contains("dolby") || gamma.contains("hdr") {
            mode = .dolbyVision
        } else if gamma.contains("standard") || gamma.contains("vivid") {
            mode = .normal
        } else {
            mode = nil
        }
        if let mode { rememberShotColor(mode, for: file) }
        return mode
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
        CameraMedia.existingFile(mediaThumbDest(file))
    }

    func isDownloaded(_ file: MediaFile) -> Bool {
        guard let url = localURL(for: file) else { return false }
        guard file.sizeBytes > 0 else { return true }
        let onDisk =
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .uint64Value ?? 0
        return onDisk >= file.sizeBytes * 9 / 10
    }

    func remotePlaybackURL(for file: MediaFile) -> URL? {
        MediaHTTP.previewPaths(file).lazy.compactMap { MediaHTTP.pathURL(storage: 0, path: $0, route: self.profile.media) }
            .first
    }

    func localPlaybackSource(for file: MediaFile) -> MediaPlaybackSource? {
        if let proxy = localProxySource(for: file) { return proxy }
        if isDownloaded(file), let local = localURL(for: file) {
            return MediaPlaybackSource(
                url: local, mimeType: MediaHTTP.playbackMIMEType(for: file.path), isRemote: false,
                path: file.path)
        }
        return nil
    }

    /// 720p `.lrv` sidecar, never the original.
    func localProxySource(for file: MediaFile) -> MediaPlaybackSource? {
        for path in MediaHTTP.proxyPaths(file) {
            if let existing = CameraMedia.existingFile(mediaPlaybackDest(file, path: path)) {
                return MediaPlaybackSource(
                    url: existing, mimeType: MediaHTTP.playbackMIMEType(for: path),
                    isRemote: false, path: path)
            }
        }
        return nil
    }

    func isAvailableOffline(_ file: MediaFile) -> Bool {
        localPlaybackSource(for: file) != nil
    }

    var canReachCameraMedia: Bool {
        guard case .live = phase else { return false }
        return backend.isControlReady
    }

    func resolvePlaybackSource(for file: MediaFile) async -> MediaPlaybackSource? {
        localPlaybackSource(for: file)
    }

    func remainingPlaybackSources(
        for file: MediaFile, after source: MediaPlaybackSource
    ) -> [MediaPlaybackSource] {
        MediaHTTP.previewPaths(file).filter { $0 != source.path }.compactMap { path in
            MediaHTTP.pathURL(storage: 0, path: path, route: profile.media).map {
                MediaPlaybackSource(
                    url: $0, mimeType: MediaHTTP.playbackMIMEType(for: path), isRemote: true,
                    path: path)
            }
        }
    }

    func cachePlaybackFile(file: MediaFile, path: String) async throws -> URL {
        let dest = mediaPlaybackDest(file, path: path)
        if let existing = CameraMedia.existingFile(dest) { return existing }
        guard canReachCameraMedia else { throw MediaTransferError.timeout }
        mediaDownloadProgress[file.path] = 0
        do {
            try await fetchMediaFile(file: file, path: path, to: dest)
            if path == file.path {
                finishDownloadProgress(file.path)
            } else {
                mediaCacheRevision &+= 1
                mediaDownloadProgress[file.path] = nil
            }
            return dest
        } catch {
            mediaDownloadProgress[file.path] = nil
            throw error
        }
    }

    private func mediaPlaybackDest(_ file: MediaFile, path: String) -> URL {
        cameraMedia.playbackCacheURL(cameraID: mediaCameraID, file: file, path: path)
    }

    func deleteMedia(_ file: MediaFile) {
        Task { await self.deleteMedia(file) }
    }

    func deleteMedia(_ file: MediaFile) async {
        guard canReachCameraMedia else {
            mediaNote = MediaOperatorCopy.notConnected
            return
        }
        do {
            try await backend.deleteFile(uri: file.path)
            ControlLiveLog.line("media: deleted \(file.filename)")
            dropMediaFile(path: file.path)
        } catch {
            ControlLiveLog.line("media: delete failed \(file.filename) \(error.localizedDescription)")
            mediaNote = MediaOperatorCopy.deleteFailed
        }
    }

    /// Luna's phone protocol has no favorite write (the official app keeps them local too).
    func toggleMediaFavorite(_ file: MediaFile) {
        let on = !isMediaFavorite(file)
        applyLocalFavorite(path: file.path, on: on)
        if let idx = mediaFiles.firstIndex(where: { $0.path == file.path }) {
            mediaFiles[idx].isStarred = on
        }
    }

    func isMediaFavorite(_ file: MediaFile) -> Bool {
        file.isStarred || mediaLocalFavorites.contains(file.path)
    }

    func isFavorite(_ file: MediaFile) -> Bool { isMediaFavorite(file) }

    func toggleFavorite(_ file: MediaFile) { toggleMediaFavorite(file) }

    func deleteMediaFiles(_ files: [MediaFile]) async {
        for file in files { await deleteMedia(file) }
    }

    func resetMediaSession() {
        persistMediaCatalog()
        cameraMedia.resetSession()
        isBrowsingMedia = false
        mediaFetchInProgress = false
        mediaNote = nil
        mediaDownloadProgress = [:]
        loadCachedCatalogIfNeeded()
        loadMediaFavorites()
    }

    func clearMediaCache() async throws {
        cameraMedia.resetSession()
        mediaDownloadProgress = [:]
        defer { mediaCacheRevision &+= 1 }
        try await cameraMedia.clearCache(cameraID: mediaCameraID, preservingCatalog: true)
    }

    private func publishMediaFiles(_ files: [MediaFile]) {
        mediaFiles = files
        mediaFetchListedCount = files.count
        persistMediaCatalog()
    }

    func persistMediaCatalog() {
        guard !mediaFiles.isEmpty else { return }
        cameraMedia.persistCatalog(mediaFiles, cameraID: mediaCameraID)
    }

    func loadCachedCatalogIfNeeded() {
        if mediaFiles.isEmpty {
            mediaFiles = cameraMedia.loadCatalog(cameraID: mediaCameraID)
        }
        mediaFetchListedCount = mediaFiles.count
    }

    private func applyFavoriteOverlay(_ file: MediaFile) -> MediaFile {
        var next = file
        if mediaLocalFavorites.contains(file.path) { next.isStarred = true }
        return next
    }

    private func dropMediaFile(path: String) {
        mediaFiles.removeAll { $0.path == path }
        mediaFetchListedCount = mediaFiles.count
        mediaDownloadProgress[path] = nil
        cameraMedia.favorites.remove(path)
        mediaLocalFavorites = cameraMedia.favorites
        cameraMedia.persistFavorites()
        persistMediaCatalog()
    }

    private func applyLocalFavorite(path: String, on: Bool) {
        if on {
            cameraMedia.favorites.insert(path)
        } else {
            cameraMedia.favorites.remove(path)
        }
        mediaLocalFavorites = cameraMedia.favorites
        cameraMedia.persistFavorites()
    }

    func loadMediaFavorites() {
        mediaLocalFavorites = cameraMedia.loadFavorites(cameraID: mediaCameraID)
    }

    private static let lastMediaCameraKey = "opc.media.lastCameraID"

    /// Cache lives under the camera id. After disconnect keep the last id so cached
    /// clips stay findable offline.
    var mediaCameraID: String {
        if let id = connectedCamera?.id.uuidString {
            if UserDefaults.standard.string(forKey: Self.lastMediaCameraKey) != id {
                UserDefaults.standard.set(id, forKey: Self.lastMediaCameraKey)
            }
            return id
        }
        return UserDefaults.standard.string(forKey: Self.lastMediaCameraKey) ?? "unknown"
    }

    private func mediaThumbDest(_ file: MediaFile) -> URL {
        cameraMedia.thumbnailCacheURL(cameraID: mediaCameraID, file: file)
    }

    private func mediaFileDest(_ file: MediaFile) -> URL {
        cameraMedia.fileCacheURL(cameraID: mediaCameraID, file: file)
    }

    private func fetchMediaFile(file: MediaFile, path: String, to dest: URL) async throws {
        guard let url = MediaHTTP.pathURL(storage: 0, path: path, route: profile.media) else {
            throw MediaTransferError.badResponse
        }
        try await cameraMedia.downloadFile(
            from: url, to: dest, path: file.path,
            expectedSize: path == file.path ? file.sizeBytes : 0
        ) { [weak self] progress in
            self?.mediaDownloadProgress[file.path] = progress
        }
    }
}

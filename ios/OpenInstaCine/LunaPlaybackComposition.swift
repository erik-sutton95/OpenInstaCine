import Foundation
import OpenCineAppKit
import OpenCineMedia
import OpenPocketViewCore

/// Camera/profile facts kept out of the shared item/load owner.
struct LunaPlaybackLook: Equatable, Sendable {
    let color: ColorMode
    let shotColor: ColorMode?
    let family: CameraBodyFamily
    let cameraName: String?
    let file: MediaFile
    let cameraID: String
}
typealias LunaPlaybackModel = MonitorMediaPlaybackModel<LunaMediaLibraryPayload, LunaPlaybackLook>

@MainActor extension CameraSession {
    func makeMediaPlayback(native: any MonitorPlaybackPort, previousColor: @escaping @MainActor () -> ColorMode?) -> LunaPlaybackModel {
        LunaPlaybackModel(library: mediaLibrary, native: native,
            candidates: { [weak self] record in self?.playbackCandidates(record) ?? [] },
            resolveLook: { [weak self] record, item in
                guard let self else { return nil }
                return await self.resolvePlaybackLook(record: record, item: item, previousColor: previousColor())
            })
    }
    func mediaPlaybackRecord(for file: MediaFile) -> MonitorMediaRecord<LunaMediaLibraryPayload>? {
        if let record = mediaRecord(for: file) { return record }
        #if targetEnvironment(simulator)
        if MonitorMediaReview.isActive, file.path.hasPrefix(MonitorMediaReview.pathPrefix) {
            // The existing opt-in simulator review passes synthetic files directly, outside its
            // catalog, with or without supplied footage: the player's controls work without it, as
            // on main. Use the real legacy codec for immutable cached-file facts, without a service.
            let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
            return try? codec.decode(JSONEncoder().encode([file])).first
        }
        #endif
        return nil
    }
    private func playbackCandidates(_ record: MonitorMediaRecord<LunaMediaLibraryPayload>) -> [MonitorPlaybackCandidate] {
        let file = record.payload.file
        #if targetEnvironment(simulator)
        if let url = MonitorMediaReview.clipURL(for: file) {
            return [.cached(.init(url: url, mimeType: "video/mp4", sourceKey: file.path))]
        }
        #endif
        var choices: [MonitorPlaybackCandidate] = []
        func cached(_ source: MediaPlaybackSource) -> MonitorPlaybackCandidate {
            .cached(.init(url: source.url, mimeType: source.mimeType, sourceKey: source.path,
                role: MediaHTTP.proxyPaths(file).contains(source.path) ? .proxy : .original, isRemote: source.isRemote))
        }
        func remote(_ path: String) -> MonitorPlaybackCandidate? {
            let role: MediaRepresentationRole = path == file.path ? .original : .proxy
            if let representation = record.asset.representations.first(where: {
                ($0.role == .original && path == file.path) || ($0.role == .proxy && path == file.proxyPath)
            }), mediaLibrary.canTransfer {
                return .representation(representation.id, mimeType: MediaHTTP.playbackMIMEType(for: path), sourceKey: path)
            }
            guard let url = MediaHTTP.pathURL(storage: 0, path: path, route: profile.media) else { return nil }
            let io = cameraMedia.nativeIO
            return .download(address: cameraMedia.playbackAddress(file: file, path: path),
                mimeType: MediaHTTP.playbackMIMEType(for: path), sourceKey: path, role: role,
                transfer: { sink in
                    try await io.transfer(from: url,
                        expectedByteCount: path == file.path && file.sizeBytes > 0 ? file.sizeBytes : nil, into: sink)
                })
        }
        // Preserve source choices and Apple native-failure retry order exactly.
        if let proxy = localProxySource(for: file) { choices.append(cached(proxy)) }
        if canReachCameraMedia { choices += MediaHTTP.proxyPaths(file).compactMap(remote) }
        if let local = localPlaybackSource(for: file) { choices.append(cached(local)) }
        if canReachCameraMedia, let original = remote(MediaHTTP.deliveryPath(file)) { choices.append(original) }
        return choices
    }
    private func resolvePlaybackLook(record: MonitorMediaRecord<LunaMediaLibraryPayload>, item: MonitorPlaybackItem, previousColor: ColorMode?) async
        -> MonitorPlaybackLook<LunaPlaybackLook>? {
        let file = record.payload.file, cameraID = mediaCameraID
        let clip: ColorMode?
        if let original = localURL(for: file), let mode = ClipColorProfileIO.shotColor(at: original, path: file.path) {
            clip = mode
        } else if let mode = ClipColorProfileIO.shotColor(at: item.url, path: item.sourceKey) {
            clip = mode
        } else if let cached = shotColor(for: file) {
            clip = cached
        } else if let gamma = record.payload.source?.metadata?.gammaMode?.lowercased() {
            if gamma.contains("log") { clip = .iLog }
            else if gamma.contains("dolby") || gamma.contains("hdr") { clip = .dolbyVision }
            else if gamma.contains("standard") || gamma.contains("vivid") { clip = .normal }
            else { clip = nil }
        } else { clip = nil }
        guard let color = PlaybackLUTColor.resolve(clip: clip, live: status.colorMode,
            last: OperatorPrefs.lastMonitorColorMode ?? previousColor) else { return nil }
        return .init(transfer: MonitorTransfer(color), source: .init(color: color, shotColor: clip,
            family: bodyFamily, cameraName: connectedCamera?.model.name, file: file, cameraID: cameraID))
    }
}

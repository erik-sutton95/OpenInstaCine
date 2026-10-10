import OpenCineApple
import OpenCineCameraControls
import OpenCineAppKitApple
import Observation
import AVFoundation
import Foundation
import OpenCineAppKit
import OpenCineMedia
import OpenInstaViewCore

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
        let owner = LunaPlaybackModel(library: mediaLibrary, native: native,
            candidates: { [weak self] record in self?.playbackCandidates(record) ?? [] },
            resolveLook: { [weak self] record, item in
                guard let self else { return nil }
                return await self.resolvePlaybackLook(record: record, item: item, previousColor: previousColor())
            })
        owner.setItemAdmission { [weak self] record in
            self?.capturePlaybackPresentation(record) ?? .init { false }
        }
        if let apple = native as? MonitorApplePlaybackOwner {
            apple.sourceAdmission = { [weak owner] in
                guard let owner else { return false }
                let captured = owner.token, accepted = owner.isActive
                guard owner.token == captured, !owner.closed else { return false }
                if accepted { return true }
                owner.close(); return false
            }
        }
        return owner
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
        if let original = localURL(for: file), let mode = ClipColorProfile.shotColor(at: original, path: file.path) {
            clip = mode
        } else if let mode = ClipColorProfile.shotColor(at: item.url, path: item.sourceKey) {
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
            last: LUTPreferences.app.lastMonitorColorMode ?? previousColor) else { return nil }
        return .init(transfer: MonitorTransfer(color), source: .init(color: color, shotColor: clip,
            family: bodyFamily, cameraName: connectedCamera?.model.name, file: file, cameraID: cameraID))
    }
}

/// Bounded native/source construction. Shared operators own the complete page lifetime.
@MainActor @Observable final class LunaPlaybackPresentationSource {
    @ObservationIgnored private var currentNative: MonitorApplePlaybackOwner?
    @ObservationIgnored private var currentAssists: MonitorPlaybackAssistSession?
    var native: MonitorApplePlaybackOwner? {
        access(keyPath: \.native); return currentNative
    }
    var assists: MonitorPlaybackAssistSession? {
        access(keyPath: \.assists); return currentAssists
    }
    func makeOwner(model: AppModel) -> MonitorOperatorMediaModel<LunaMediaLibraryPayload, LunaPlaybackLook> {
        MonitorOperatorMediaModel(library: model.session.mediaLibrary,
            recordAdmission: { record in model.session.capturePlaybackPresentation(record) },
            makeAdmittedPlayback: { [self] _, admission in
                currentAssists?.close()
                guard admission.isCurrent() else { return nil }
                let native = MonitorApplePlaybackOwner(feed: PlaybackFeedSession())
                let player = model.session.makeMediaPlayback(native: native,
                    previousColor: { model.assist.monitorColorMode })
                let assists = MonitorPlaybackAssistSession(audioSession: model.playbackAudioSession,
                    native: native, samples: model.frameSamples,

                    onTapFailure: MediaPlaybackAudioSession.tapFailure,
                    onAudioFailure: MediaPlaybackAudioSession.audioFailure)
                guard admission.isCurrent() else { assists.close(); player.close(); return nil }
                currentNative = native; currentAssists = assists
                withMutation(keyPath: \.native) {}; withMutation(keyPath: \.assists) {}
                guard admission.isCurrent() else { assists.close(); player.close(); return nil }
                return player
            })
    }
    func operations(model: AppModel,
        owner: MonitorOperatorMediaModel<LunaMediaLibraryPayload, LunaPlaybackLook>) -> MonitorOperatorPlaybackOperations<LunaMediaLibraryPayload, LunaPlaybackLook> {
        let cache: (@MainActor (MonitorMediaRecord<LunaMediaLibraryPayload>) async -> Void)?
        let delete: (@MainActor (MonitorMediaRecord<LunaMediaLibraryPayload>) async -> Bool)?
        if model.session.canReachCameraMedia {
            cache = { record in await model.session.download(file: record.payload.file) }
            delete = { record in
                await model.session.deleteMediaFiles([record.payload.file])
                return model.session.mediaLibrary.record(record.asset.id) == nil
            }
        } else { cache = nil; delete = nil }
        return .init(cacheOriginal: cache, delete: delete,
            favorite: { record in model.session.toggleFavorite(record.payload.file) }, adoptLook: { _, look in
            let value = look.source
            guard let player = owner.playback else { return }
            let token = player.token
            guard owner.isCurrent(token) else { return }
            if let shot = value.shotColor { model.session.rememberShotColor(shot, for: value.file) }
            guard owner.isCurrent(token) else { return }
            model.assist.adoptPlaybackColor(value.color,
                family: value.family != .other ? value.family : model.assist.monitorFamily,
                cameraName: value.cameraName,
                lookProfile: model.session.connectedCamera?.model.captureProfile?.looks ?? LunaShellMapping.lookProfile)
        })
    }
    func values(record: MonitorMediaRecord<LunaMediaLibraryPayload>, model: AppModel) -> MonitorPlaybackSourceValues {
        let file = record.payload.file
        let grade = model.session.cacheGrade(for: file)
        let availability: MonitorPlaybackAvailability
        #if targetEnvironment(simulator)
        if MonitorMediaReview.clipURL(for: file) != nil { availability = .original }
        else { availability = grade == .original ? .original : grade.isProxyOnly ? .proxy : .camera }
        #else
        availability = grade == .original ? .original : grade.isProxyOnly ? .proxy : .camera
        #endif
        let transfer = model.monitorTransfer ?? model.assist.monitorColorMode.map(MonitorTransfer.init)
        let buffered = currentNative?.player.currentItem?.loadedTimeRanges.map {
            CMTimeGetSeconds(CMTimeRangeGetEnd($0.timeRangeValue))
        }.filter(\.isFinite).max()
        return .init(availability: availability,
            progress: model.session.mediaDownloadProgress[file.path], buffered: buffered,
            colorLabel: model.session.shotColor(for: file)?.label(in: model.session.profile),
            transfer: transfer,
            clipByte: transfer.map { model.frameSamples.exposureCeiling.clipByte(transfer: $0) })
    }
}

@MainActor extension CameraSession {
    func capturePlaybackPresentation(_ record: MonitorMediaRecord<LunaMediaLibraryPayload>) -> MonitorPlaybackAdmission {
        let owner: MonitorMediaLibraryModel<LunaMediaLibraryPayload> = mediaLibrary
        let token = owner.actionToken, generation = owner.cache.directory.generation
        let cameraID = mediaCameraID
        let indexed = owner.record(record.asset.id) != nil
        return .init { [weak self, weak owner] in
            guard let self, let owner, self.mediaLibrary === owner,
                owner.isCurrent(token), owner.cache.directory.generation == generation,
                self.mediaCameraID == cameraID else { return false }
            if indexed { return owner.record(record.asset.id) != nil }
            #if targetEnvironment(simulator)
            return MonitorMediaReview.isActive && record.payload.file.path.hasPrefix(MonitorMediaReview.pathPrefix)
            #else
            return false
            #endif
        }
    }
}

import OpenCineApple
import OpenCineCameraControls
import OpenCineAppKitApple
import AVFoundation
import Foundation
import Insta360Apple
import enum Insta360Protocol.LunaColorMode
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
        mediaRecord(for: file)
    }
    private func playbackCandidates(_ record: MonitorMediaRecord<LunaMediaLibraryPayload>) -> [MonitorPlaybackCandidate] {
        let file = record.payload.file
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
        } else {
            clip = LunaColorMode(gammaLabel: record.payload.source?.metadata?.gammaMode)
                .map(LunaShellMapping.colorMode)
        }
        guard let color = PlaybackLUTColor.resolve(clip: clip, live: status.colorMode,
            last: LUTPreferences.app.lastMonitorColorMode ?? previousColor) else { return nil }
        return .init(transfer: MonitorTransfer(color), source: .init(color: color, shotColor: clip,
            family: bodyFamily, cameraName: connectedCamera?.model.name, file: file, cameraID: cameraID))
    }
}

/// Insta's camera source for the shared playback host: the page runtime over Insta's feed,
/// its presentation admission, operations and per-record values.
@MainActor final class LunaPlaybackPresentationSource: MonitorPlaybackPresentationSource {
    let presentation: MonitorApplePlaybackPresentation<LunaMediaLibraryPayload, LunaPlaybackLook>
    private let model: AppModel
    init(model: AppModel) {
        self.model = model
        presentation = .init(makeFeed: { PlaybackFeedSession() }, audioSession: model.playbackAudioSession,
            samples: { model.frameSamples },
            onTapFailure: MediaPlaybackAudioSession.tapFailure,
            onAudioFailure: MediaPlaybackAudioSession.audioFailure)
    }
    func makeOwner() -> MonitorOperatorMediaModel<LunaMediaLibraryPayload, LunaPlaybackLook> {
        let model = model
        return presentation.makeOwner(library: model.session.mediaLibrary,
            recordAdmission: { record in model.session.capturePlaybackPresentation(record) },
            makePlayback: { native in
                model.session.makeMediaPlayback(native: native, previousColor: { model.assist.monitorColorMode })
            })
    }
    func operations(
        owner: MonitorOperatorMediaModel<LunaMediaLibraryPayload, LunaPlaybackLook>) -> MonitorOperatorPlaybackOperations<LunaMediaLibraryPayload, LunaPlaybackLook> {
        let model = model
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
    func values(record: MonitorMediaRecord<LunaMediaLibraryPayload>,
        owner: MonitorOperatorMediaModel<LunaMediaLibraryPayload, LunaPlaybackLook>) -> MonitorPlaybackSourceValues {
        let file = record.payload.file
        let grade = model.session.cacheGrade(for: file)
        let availability: MonitorPlaybackAvailability =
            grade == .original ? .original : grade.isProxyOnly ? .proxy : .camera
        let transfer = model.monitorTransfer ?? model.assist.monitorColorMode.map(MonitorTransfer.init)
        return .init(availability: availability,
            progress: model.session.mediaLibrary.progress[record.asset.id],
            colorLabel: model.session.shotColor(for: file)?.label(in: model.session.profile),
            transfer: transfer,
            clipByte: transfer.map { model.frameSamples.exposureCeiling.clipByte(transfer: $0) },
            bufferedThroughSeconds: presentation.bufferedThroughSeconds(record: record, owner: owner))
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
            return indexed && owner.record(record.asset.id) != nil
        }
    }
}

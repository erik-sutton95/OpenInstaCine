import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineMedia
import OpenInstaViewCore
import SwiftUI
import UIKit

// MARK: - Photo viewer

/// Source addresses and bounded UIKit decoding; the shared photo host owns the complete page.
struct MediaPhotoViewer: View {
    let opening: MonitorMediaGalleryOpen<LunaMediaLibraryPayload>
    let library: MonitorMediaLibraryModel<LunaMediaLibraryPayload>
    let session: CameraSession
    @Environment(AppModel.self) private var model

    var body: some View {
        let captured = session
        let origin = model.shell.monitor?.id
        MonitorOperatorPhotoHost(opening: opening, library: library, host: model, values: .app,
            loaders: loaders(captured), operations: operations(captured),
            sourceCurrent: { [weak model, weak captured] in
                guard let model, let captured else { return false }
                return model.session === captured && captured.mediaLibrary === library
                    && model.shell.monitor?.id == origin
            }, deliveryPopup: { record, dismiss in
                MediaDeliveryPopupOverlay(files: [record.payload.file], onDismiss: dismiss)
            })
    }

    private func operations(_ session: CameraSession) -> MonitorMediaGalleryOperations<LunaMediaLibraryPayload> {
        if session.canReachCameraMedia {
            return .init(delete: { record in await session.deleteMedia(record.payload.file) },
                favorite: { record in session.toggleFavorite(record.payload.file) })
        }
        return .init(favorite: { record in session.toggleFavorite(record.payload.file) })
    }

    private func loaders(_ session: CameraSession) -> MonitorMediaPictureLoaders<LunaMediaLibraryPayload, UIImage> {
        .init(preview: { request in
            guard request.isCurrent(), let url = session.thumbnailURL(for: request.record.payload.file),
                let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }, cached: { request in
            let file = request.record.payload.file
            guard request.isCurrent(), session.isDownloaded(file), let url = session.localURL(for: file) else { return nil }
            return await MediaCellImageLoader.shared.downsampled(at: url, maxPixelSize: 4096)
        }, source: { request in
            guard request.isCurrent(), session.canReachCameraMedia,
                let bytes = await session.originalImageBytes(for: request.record.payload.file, ifCurrent: request.isCurrent) else { return nil }
            return await MediaCellImageLoader.shared.downsampled(data: bytes, maxPixelSize: 4096)
        })
    }
}

// MARK: - Player

/// The camera source of the shared playback host; the host owns the complete page.
struct MediaPlayerView: View {
    let opening: MonitorMediaGalleryOpen<LunaMediaLibraryPayload>
    @Environment(AppModel.self) private var model
    init(opening: MonitorMediaGalleryOpen<LunaMediaLibraryPayload>) { self.opening = opening }

    var body: some View {
        MonitorOperatorPlaybackHost(opening: opening, host: model, values: .app,
            makeSource: { [model] in LunaPlaybackPresentationSource(model: model) },
            captureSource: { [model] in
                let captured = model.session, origin = model.shell.monitor?.id
                return .init { [weak model, weak captured] in
                    guard let model, let captured else { return false }
                    return model.session === captured && model.shell.monitor?.id == origin
                }
            }, preview: { AssistInspectorPreview(tool: $0) },
            lookMenu: { LUTAssist.longPressMenu(assist: model.assist) },
            deliveryPopup: { record, dismiss in
                MediaDeliveryPopupOverlay(files: [record.payload.file], onDismiss: dismiss)
            })
    }
}

// MARK: - Host values

extension AppModel: MonitorMediaHost {}

extension MonitorMediaPageValues where Palette == LiveDesign {
    @MainActor static var app: Self {
        .init(stores: .app, looks: .app, palette: LiveDesign.self, haptics: .app,
            cacheOriginal: { OperatorPrefs.cacheFullResolution }, configureDisplay: scopeDisplay,
            remoteDisplayName: "Frame.io", makePictureHost: { PlaybackFeedHostView() })
    }
}

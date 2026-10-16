import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineMedia
import OpenInstaViewCore
import SwiftUI
import UIKit

enum MediaClipPresentation {
    static let resolutionLevels = MonitorMediaResolutionLevel.standard
}

typealias MediaLibraryCopy = MonitorMediaGalleryCopy

struct MediaLibraryView: View {
    var safeArea: EdgeInsets = .init()
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @State private var presented: MonitorMediaGalleryOpen<LunaMediaLibraryPayload>?
    @State private var deliveryFiles: [MediaFile]?
    private var session: CameraSession { model.session }
    private var library: MonitorMediaLibraryModel<LunaMediaLibraryPayload> { session.mediaLibrary }
    private var isLive: Bool { library.canRefresh }
    private var operations: MonitorMediaGalleryOperations<LunaMediaLibraryPayload> {
        if isLive {
            return .init(download: { record in await session.download(file: record.payload.file) },
                delete: { record in await session.deleteMedia(record.payload.file) },
                favorite: { record in session.toggleFavorite(record.payload.file) })
        }
        return .init(favorite: { record in session.toggleFavorite(record.payload.file) })
    }
    var body: some View {
        MonitorOperatorCatalogScreen(library: library,
            brand: session.connectedCamera?.name ?? "OpenInstaCine", safeArea: safeArea,
            sourceAvailable: isLive, operations: operations,
            colorChoices: ColorMode.allCases.map { .init(id: String($0.rawValue), label: $0.label(in: session.profile)) },
            resolutionLevels: MediaClipPresentation.resolutionLevels,
            facts: { record in
                let file = record.payload.file
                return .init(resolution: file.resolution, byteCount: file.sizeBytes,
                    durationSeconds: file.durationSeconds, dateKey: file.dateKey,
                    colorLabel: session.shotColor(for: file)?.label(in: session.profile))
            }, begin: { library.begin() }, refresh: { library.refresh() }, close: dismiss,
            open: { presented = $0 }, share: { records, token in
                guard library.isCurrent(token) else { return }
                deliveryFiles = records.map { record in record.payload.file }
            }, thumbnail: { context in
                let record = context.record
                let file = record.payload.file
                let grade = MediaCacheGrade.resolve(hasOriginal: context.cached?.originalURL != nil,
                    hasProxy: context.cached?.proxyURL != nil)
                MonitorMediaCatalogThumbnail(cameraID: session.mediaCameraID, assetID: file.id, file: file,
                    cacheGrade: grade, localURL: context.cached?.originalURL, thumbnailURL: context.cached?.thumbnailURL,
                    isCurrent: context.isCurrent, onDuration: context.duration, source: { model.session })
            })
            .fullScreenCover(item: $presented) { request in
                if (request.record.facts.presentationKind ?? request.record.asset.kind) == .photo {
                    MediaPhotoViewer(opening: request, library: library, session: session).environment(model)
                } else {
                    MediaPlayerView(opening: request).environment(model)
                }
            }
            .overlay { MonitorOperatorDeliveryChrome(model: model.delivery.lifetime, scope: .surface, remoteDisplayName: "Frame.io") }
            .overlay {
                if let deliveryFiles {
                    MediaDeliveryPopupOverlay(files: deliveryFiles) { self.deliveryFiles = nil }
                }
            }
            .onChange(of: library.lifetimeToken) { _, _ in deliveryFiles = nil }
            #if DEBUG && targetEnvironment(simulator)
                .task(id: library.displayedRecords.first?.asset.id) {
                    // `ReviewLaunch(screen: .playback)`: open the first staged clip as a tap would. A
                    // connected camera's clip once the camera's own catalog lists it: the cached copy
                    // shown before it carries no camera facts (deletable), as on a real connection.
                    guard MonitorUIReview.opensFirstClip, let record = library.displayedRecords.first,
                        MonitorUIReview.launch?.connected != true || record.asset.deletable == true
                    else { return }
                    MonitorUIReview.opensFirstClip = false
                    presented = .init(record: record, playlist: library.displayedRecords, admission: library.actionToken)
                }
            #endif
    }
    private func dismiss() {
        if let onClose { onClose() } else { model.shell.dismissCover() }
    }
}

/// The shared gallery cell reads this session's cached and camera thumbnails.
extension CameraSession: MonitorMediaThumbnailSource {}

/// Complete shared settings and catalog composition for the shell's retained cover.
struct AppPanelHost: View {
    let cover: ShellModel.Cover

    var body: some View {
        MonitorCoverPage { safeArea in
            switch cover {
            case .settings: SettingsRootView(safeArea: safeArea)
            case .media: MediaLibraryView(safeArea: safeArea)
            }
        }
    }
}

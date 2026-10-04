import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Decodes cell images downsampled to a bounded pixel size, off the main actor.
actor MediaCellImageLoader {
    static let shared = MediaCellImageLoader()

    func downsampled(
        at url: URL, maxPixelSize: Int, fallbackOrientation: Int? = nil
    ) -> UIImage? {
        autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                return nil
            }
            return Self.downsampled(
                source: source, maxPixelSize: maxPixelSize,
                fallbackOrientation: fallbackOrientation)
        }
    }

    func downsampled(
        data: Data, maxPixelSize: Int, fallbackOrientation: Int? = nil
    ) -> UIImage? {
        autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }
            return Self.downsampled(
                source: source, maxPixelSize: maxPixelSize,
                fallbackOrientation: fallbackOrientation)
        }
    }

    private nonisolated static func exifOrientation(source: CGImageSource) -> Int? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }
        return (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
    }

    private static func downsampled(
        source: CGImageSource, maxPixelSize: Int, fallbackOrientation: Int?
    ) -> UIImage? {
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
        else { return nil }
        if let fallbackOrientation, fallbackOrientation != 1,
            exifOrientation(source: source) == nil,
            let exif = CGImagePropertyOrientation(rawValue: UInt32(fallbackOrientation))
        {
            return UIImage(cgImage: cgImage, scale: 1, orientation: UIImage.Orientation(exif))
        }
        return UIImage(cgImage: cgImage)
    }
}

@MainActor
enum MediaCellThumbnailCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 150
        return cache
    }()
}

extension UIImage.Orientation {
    fileprivate init(_ exif: CGImagePropertyOrientation) {
        switch exif {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

enum MediaCategoryTab: String, CaseIterable, Identifiable {
    case all = "All"
    case videos = "Videos"
    case photos = "Photos"
    case favorites = "Favorites"

    var id: String { rawValue }

    var opcIcon: OpcIcon {
        switch self {
        case .all: .layoutGrid
        case .videos: .film
        case .photos: .image
        case .favorites: .star
        }
    }

    var headerTitle: String {
        switch self {
        case .all: "All clips"
        case .videos: "Videos"
        case .photos: "Photos"
        case .favorites: "Favorites"
        }
    }

    var libraryTab: MediaLibraryTab {
        switch self {
        case .all: .all
        case .videos: .videos
        case .photos: .photos
        case .favorites: .favorites
        }
    }
}

enum MediaClipPresentation {
    static func resolutionLabel(_ resolution: String?) -> String? {
        guard let resolution, !resolution.isEmpty else { return nil }
        let width = resolution.split(separator: "x").first.flatMap { Int($0) }
        if let width {
            if width >= 7680 { return "8K" }
            if width >= 5120 { return "6K" }
            if width >= 3840 { return "4K" }
            if width >= 2880 { return "3K" }
            if width >= 2560 { return "2.7K" }
            if width >= 1920 { return "1080p" }
            if width >= 1280 { return "720p" }
        }
        return resolution
    }

    static func dateLabel(_ dateKey: String) -> String {
        guard dateKey.count == 8 else { return dateKey }
        let year = dateKey.prefix(4)
        let month = dateKey.dropFirst(4).prefix(2)
        let day = dateKey.suffix(2)
        return "\(year)-\(month)-\(day)"
    }

    static func metadataLine(file: MediaFile, durationOverride: String? = nil) -> String {
        var parts: [String] = []
        if let resolution = resolutionLabel(file.resolution) {
            parts.append(resolution)
        }
        let bytes = MediaClipFormatting.byteLabel(file.sizeBytes)
        if !bytes.isEmpty { parts.append(bytes) }
        if file.kind == .video {
            parts.append(
                durationOverride
                    ?? MediaClipFormatting.durationLabel(seconds: file.durationSeconds))
        }
        return parts.joined(separator: " · ")
    }
}

/// Operator-facing media-browser copy. Never name a sister app.
enum MediaLibraryCopy {
    static let filterEmpty = "Nothing in this tab matches the filters."
    static let emptyAll =
        "Nothing on this camera yet. Record a clip, then pull to refresh."
    static let emptyFavorites = "Nothing favorited yet. Star a clip to find it here."
    static let emptyVideos =
        "No videos on this camera yet. Record a clip, then pull to refresh."
    static let emptyPhotos =
        "No photos on this camera yet. Capture a still, then pull to refresh."
    static let disconnected = "Connect the camera to list clips on the body."
    static let disconnectedEmptyCache =
        "Nothing cached on this phone. Connect the camera to list clips on the body."
    static let proxyTag = "Proxy"
    static let proxyHelp = "720p preview. Connect the camera to share the original."
}

struct MediaLibraryView: View {
    /// Host-processed insets (OpenZCine `MediaBrowserView.safeArea`). Do not read
    /// GeometryReader safeAreaInsets here — this surface `ignoresSafeArea()`.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var isFilterPopupPresented = false
    @State private var pickingDate: FilterDateBound?
    @State private var isBatchDeleteConfirmPresented = false
    @State private var playingFile: MediaFile?
    @State private var viewingPhoto: MediaFile?
    @State private var deliveryFiles: [MediaFile]?
    @State private var resolvedDurations: [String: String] = [:]
    private var session: CameraSession { model.session }
    private var library: MonitorMediaLibraryModel<LunaMediaLibraryPayload> { session.mediaLibrary }
    private var isLive: Bool { library.canRefresh }
    private var displayedFiles: [MediaFile] { library.displayedRecords.map { record in
        var file = record.payload.file; file.isStarred = record.favorite; return file
    } }
    private func cachedEntry(_ file: MediaFile) -> MonitorMediaCacheEntry? {
        session.mediaRecord(for: file).flatMap { library.entries[$0.asset.id] }
    }
    private func cachedGrade(_ file: MediaFile) -> MediaCacheGrade {
        let entry = cachedEntry(file)
        return .resolve(hasOriginal: entry?.originalURL != nil, hasProxy: entry?.proxyURL != nil)
    }
    private var displayedVideos: [MediaFile] {
        displayedFiles.filter { $0.kind == .video }
    }

    private var filterSourceFiles: [MediaFile] { library.records(in: library.category).map(\.payload.file) }
    private var formatOptions: [String] {
        Array(Set(filterSourceFiles.map(\.fileExtension)).filter { !$0.isEmpty }).sorted()
    }

    private var resolutionOptions: [String] {
        Array(Set(filterSourceFiles.compactMap(\.resolution)).filter { !$0.isEmpty }).sorted()
    }

    private var colorOptions: [ColorMode] {
        let present = Set(library.records(in: library.category).compactMap { $0.facts.color.flatMap(UInt8.init) })
        return ColorMode.allCases.filter { present.contains($0.rawValue) }
    }
    private var dateBounds: ClosedRange<Date>? {
        let dates = filterSourceFiles.compactMap { MediaLibraryQuery.date(fromKey: $0.dateKey) }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }

    private var activeFilterCount: Int { library.activeFilterCount }
    private var hasActiveFilters: Bool { activeFilterCount > 0 }
    private var selectedFiles: [MediaFile] { library.selectedRecords.map(\.payload.file) }
    private func mediaPermissions(_ file: MediaFile) -> MonitorMediaPermissions {
        var permissions: MonitorMediaPermissions = [.favorite]
        let asset = session.mediaRecord(for: file)?.asset
        let canTransfer = library.canTransfer && asset?.representations.contains { $0.role == .original } == true
        if canTransfer || cachedGrade(file) == .original { permissions.insert(.share) }
        if canTransfer && cachedGrade(file) != .original { permissions.insert(.cache) }
        if library.canDelete && asset?.deletable == true { permissions.insert(.delete) }
        return permissions
    }

    private var catalogItems: [MonitorMediaItem] {
        displayedFiles.map { file in
            let grade = cachedGrade(file)
            let color = session.shotColor(for: file)?.label(in: session.profile) ?? ""
            let metadata = MediaClipPresentation.metadataLine(
                file: file, durationOverride: resolvedDurations[file.id])
            return MonitorMediaItem(
                id: session.mediaRecord(for: file)!.asset.id.rawValue, filename: file.filename,
                metadata: color.isEmpty ? metadata : "\(color) · \(metadata)",
                format: file.resolution ?? "", color: color,
                duration: file.kind == .photo
                    ? ""
                    : resolvedDurations[file.id]
                        ?? (file.durationSeconds > 0
                            ? MediaClipFormatting.durationLabel(seconds: file.durationSeconds)
                            : ""),
                date: MediaClipPresentation.dateLabel(file.dateKey),
                availability: grade == .original ? .original : grade.isProxyOnly ? .proxy : .camera,
                progress: session.mediaDownloadProgress[file.path],
                favorite: session.isFavorite(file), photo: file.kind == .photo,
                permissions: mediaPermissions(file)
            )
        }
    }

    private var catalogCategories: [MonitorMediaCategory] {
        MediaCategoryTab.allCases.map { tab in
            MonitorMediaCategory(id: tab.rawValue, title: tab.rawValue,
                count: library.records(in: MonitorMediaCategoryFilter(rawValue: tab.rawValue.lowercased())!).count)
        }
    }
    private var categoryTitle: String { library.category.rawValue.capitalized }
    private var sortTitle: String { library.sort.rawValue.capitalized }

    var body: some View {
        @Bindable var library = library
        let filesByID = Dictionary(library.displayedRecords.map { ($0.asset.id.rawValue, $0.payload.file) },
            uniquingKeysWith: { _, latest in latest })
        ZStack(alignment: .topLeading) {
            LiveDesign.background

            MonitorMediaCatalog(
                brand: session.connectedCamera?.name ?? "OpenInstaCine", safeArea: safeArea,
                items: catalogItems, categories: catalogCategories, category: categoryTitle,
                layout: library.layout,
                thumbnailSize: library.thumbnailSize,
                sortTitle: sortTitle,
                status: isLive ? "Camera + local cache" : "Available on this phone",
                selectedIDs: Set(library.selectedIDs.map(\.rawValue)), selecting: library.selecting,
                refreshing: library.fetching, canRefresh: library.canRefresh,
                tablet: UIDevice.current.userInterfaceIdiom == .pad,
                action: handleCatalogAction
            ) { item in
                if let file = filesByID[item.id] {
                    MediaCatalogThumbnail(
                        cameraID: session.mediaCameraID, file: file, cacheGrade: cachedGrade(file),
                        localURL: cachedEntry(file)?.originalURL,
                        thumbnailURL: cachedEntry(file)?.thumbnailURL,
                        onDuration: { resolvedDurations[file.id] = $0 }
                    )
                }
            } empty: {
                if session.mediaFetchInProgress { listingState } else { emptyState }
            } filters: {
                filterButton
            }

            if isFilterPopupPresented {
                filterPopup
            }

            if let state = model.delivery.overlayState {
                VStack {
                    MediaDeliveryOverlay(state: state) {
                        model.delivery.cancel()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(true)
            }

        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: library.thumbnailSize)
        .animation(.easeInOut(duration: 0.2), value: library.layout)
        .confirmationDialog(
            "Delete \(library.selectedIDs.count) items from the camera?",
            isPresented: $isBatchDeleteConfirmPresented, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let files = selectedFiles
                Task {
                    await session.deleteMediaFiles(files)
                    exitSelectionMode()
                }
            }
        }
        .onAppear { library.begin() }
        .fullScreenCover(item: $playingFile) { file in
            MediaPlayerView(files: displayedVideos, startingAt: file)
                .environment(model)
        }
        .fullScreenCover(item: $viewingPhoto) { file in
            MediaPhotoViewer(file: file)
                .environment(model)
        }
        .overlay {
            if let deliveryFiles {
                MediaDeliveryPopupOverlay(files: deliveryFiles) {
                    self.deliveryFiles = nil
                }
            }
        }
        .sheet(item: model.delivery.sharePresentation) { payload in
            MediaShareSheet(urls: payload.urls) {
                model.delivery.completeSharePresentation(id: payload.id)
            }
        }
        .sheet(item: $pickingDate) { bound in
            FilterCalendarSheet(
                title: bound.title,
                range: dateBounds ?? Date.distantPast...Date.distantFuture,
                key: bound == .start ? $library.dateStart : $library.dateEnd
            )
        }
        .onChange(of: library.dateStart) { _, start in
            if let start, let end = library.dateEnd, start > end { library.dateEnd = start }
        }
        .onChange(of: library.dateEnd) { _, end in
            if let end, let start = library.dateStart, end < start { library.dateStart = end }
        }
    }

    private func dismiss() {
        session.endMediaBrowse()
        if let onClose {
            onClose()
        } else {
            model.shell.dismissCover()
        }
    }

    // MARK: - Sidebar / strip

    private func handleCatalogAction(_ action: MonitorMediaAction) {
        switch action {
        case .back: dismiss()
        case .refresh: library.refresh()
        case .cycleSort:
            let values = MonitorMediaSort.allCases
            library.sort = values[(values.firstIndex(of: library.sort)! + 1) % values.count]
        case .category(let id):
            if let category = MonitorMediaCategoryFilter(rawValue: id.lowercased()) { library.category = category }
        case .layout(let value): library.layout = value
        case .thumbnailSize(let value): library.thumbnailSize = value
        case .open(let id):
            if let record = library.record(.init(id)) { open(record.payload.file) }
        case .select(let id):
            if let record = library.record(.init(id)) {
                if library.selecting { toggleSelection(record.asset.id) } else { beginSelection(with: record.asset.id) }
            }
        case .selection(let ids):
            if !library.selecting { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            library.selecting = true; library.selectedIDs = Set(ids.map { MediaAssetID($0) })
        case .favorite(let id): library.toggleFavorite(.init(id))
        case .selectAll: library.selectAll()
        case .clearSelection: library.clearSelection()
        case .shareSelection:
            let files = selectedFiles
            if !files.isEmpty, files.allSatisfy({ mediaPermissions($0).contains(.share) }) { deliveryFiles = files }
        case .cacheSelection:
            let ids = library.selectedRecords.filter { mediaPermissions($0.payload.file).contains(.cache) }.map(\.asset.id)
            Task { for id in ids { _ = try? await library.cacheOriginal(id) } }
        case .favoriteSelection:
            for record in library.selectedRecords where !record.favorite { library.toggleFavorite(record.asset.id) }
        case .deleteSelection:
            if !selectedFiles.isEmpty, selectedFiles.allSatisfy({ mediaPermissions($0).contains(.delete) }) {
                isBatchDeleteConfirmPresented = true
            }
        }
    }

    private var filterButton: some View {
        let on = isFilterPopupPresented || hasActiveFilters
        return Button {
            isFilterPopupPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                MonitorIcon.listFilter.view().frame(width: 13, height: 13)
                Text("Filter").font(MonitorTheme.font(10.5, weight: .semibold)).lineLimit(1)
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(MonitorTheme.font(10.5, weight: .semibold))
                }
            }
            .foregroundStyle(on ? MonitorTheme.text : MonitorTheme.secondary)
            .padding(.horizontal, 11).frame(minWidth: 44, minHeight: 44)
            .background(
                on ? MonitorTheme.accent.opacity(0.18) : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(MonitorButtonStyle())
        .accessibilityLabel("Filter library")
        .accessibilityValue(
            activeFilterCount == 0 ? "Off" : "\(activeFilterCount) active"
        )
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("monitor.media.filter")
    }

    private var filterPopup: some View {
        GeometryReader { proxy in
            let physical = windowGeometry.safeArea
            let card = MonitorMediaFilterPopupLayout.card(
                viewportWidth: proxy.size.width, viewportHeight: proxy.size.height,
                safeTop: max(safeArea.top, physical.top),
                safeLeading: max(safeArea.leading, physical.leading),
                safeBottom: max(safeArea.bottom, physical.bottom),
                safeTrailing: max(safeArea.trailing, physical.trailing),
                topControlInset: windowGeometry.topControlInset)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { isFilterPopupPresented = false }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("FILTER")
                            .font(MonitorTheme.font(10, weight: .bold)).monospacedDigit()
                            .kerning(0.8)
                            .foregroundStyle(LiveDesign.muted)
                        Spacer()
                        CloseButton(action: { isFilterPopupPresented = false }, size: 26)
                    }

                    ScrollView {
                        MonitorMediaFilterForm(
                            formats: formatOptions, resolutions: resolutionOptions,
                            colors: colorOptions.map {
                                MonitorMediaFilterForm.ColorOption(
                                    id: $0.rawValue, label: $0.label(in: session.profile))
                            },
                            formatSelection: library.formats, resolutionSelection: library.resolutions,
                            colorSelection: Set(library.colors.compactMap(UInt8.init)),
                            dateStartLabel: library.dateStart.map(MediaClipPresentation.dateLabel),
                            dateEndLabel: library.dateEnd.map(MediaClipPresentation.dateLabel),
                            hasDates: dateBounds != nil,
                            onToggleFormat: { toggle($0, in: &library.formats) },
                            onToggleResolution: { toggle($0, in: &library.resolutions) },
                            onToggleColor: { toggle(String($0), in: &library.colors) },
                            onPickStart: { pickingDate = .start },
                            onPickEnd: { pickingDate = .end },
                            onClear: { library.resetFilters() }
                            )
                    }
                    .monitorScrollFade()
                }
                .padding(16)
                .frame(width: card.width, height: card.height, alignment: .topLeading)
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .offset(x: card.x, y: card.y)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("monitor.media.filter.popup")
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.session.mediaFetchInProgress {
                ProgressView()
                    .tint(LiveDesign.accent)
            } else {
                OpcIcon.film
                    .frame(width: 40, height: 40)
                    .foregroundStyle(LiveDesign.faint)
            }
            Text(model.session.mediaFetchInProgress ? "Listing clips" : "No clips yet")
                .font(LiveType.ui(size: 15, weight: .medium))
                .foregroundStyle(LiveDesign.muted)
            Text(model.session.mediaNote ?? emptySubtitle)
                .font(LiveType.ui(size: 12))
                .foregroundStyle(LiveDesign.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(LiveDesign.muted)
            Text("Listing clips on camera…")
                .font(LiveType.ui(size: 15, weight: .medium))
                .foregroundStyle(LiveDesign.muted)
            Text(
                session.mediaFetchListedCount == 0
                    ? "Querying card storage…"
                    : "\(session.mediaFetchListedCount) clip\(session.mediaFetchListedCount == 1 ? "" : "s") found so far"
            )
            .font(LiveType.ui(size: 12))
            .foregroundStyle(LiveDesign.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySubtitle: String {
        if !isLive {
            return session.mediaFiles.isEmpty
                ? MediaLibraryCopy.disconnected
                : MediaLibraryCopy.disconnectedEmptyCache
        }
        if hasActiveFilters {
            return MediaLibraryCopy.filterEmpty
        }
        switch library.category {
        case .favorites: return MediaLibraryCopy.emptyFavorites
        case .videos: return MediaLibraryCopy.emptyVideos
        case .photos: return MediaLibraryCopy.emptyPhotos
        case .all: return MediaLibraryCopy.emptyAll
        }
    }

    private func open(_ file: MediaFile) {
        if library.selecting, let id = session.mediaRecord(for: file)?.asset.id {
            toggleSelection(id)
            return
        }
        if !isLive, !session.isAvailableOffline(file) { return }
        if file.kind == .photo {
            viewingPhoto = file
        } else {
            playingFile = file
        }
    }

    private func beginSelection(with id: MediaAssetID) {
        guard !library.selecting else { return }
        library.selecting = true; library.selectedIDs = [id]
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func toggleSelection(_ id: MediaAssetID) {
        if library.selectedIDs.contains(id) { library.selectedIDs.remove(id) } else { library.selectedIDs.insert(id) }
    }
    private func exitSelectionMode() { library.clearSelection() }

    private func share(_ files: [MediaFile]) async {
        guard !files.isEmpty else { return }
        deliveryFiles = files
    }

    // MARK: - Layout chrome

}

private enum FilterDateBound: String, Identifiable {
    case start, end
    var id: String { rawValue }
    var title: String { rawValue == "start" ? "Start date" : "End date" }
}

private struct FilterCalendarSheet: View {
    let title: String
    let range: ClosedRange<Date>
    @Binding var key: String?
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(title: String, range: ClosedRange<Date>, key: Binding<String?>) {
        self.title = title
        self.range = range
        self._key = key
        let parsed = key.wrappedValue.flatMap { MediaLibraryQuery.date(fromKey: $0) }
        let initial = min(max(parsed ?? Date(), range.lowerBound), range.upperBound)
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            DatePicker(
                title, selection: $date, in: range, displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.calendar, MediaLibraryQuery.filenameCalendar())
            .tint(MonitorTheme.accent)
            .padding(.horizontal, 8)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        key = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        key = MediaLibraryQuery.dateKey(from: date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// The shared library owns thumbnail acquisition; native image/metadata decoding stays here. All card,
/// grid/list and selection rendering lives in MonitorMediaCatalog.
private struct MediaCatalogThumbnail: View {
    let cameraID: String
    let file: MediaFile
    let cacheGrade: MediaCacheGrade
    let localURL: URL?
    let thumbnailURL: URL?
    let onDuration: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var thumbnail: UIImage?

    private var isPhoto: Bool { file.kind == .photo }
    private var isDownloaded: Bool { cacheGrade == .original }

    var body: some View {
        ZStack {
            MonitorTheme.surface
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                (isPhoto ? OpcIcon.image : OpcIcon.film)
                    .frame(width: 28, height: 28).foregroundStyle(MonitorTheme.faint)
            }
        }
        .clipped()
        .task(
            id:
                "\(cameraID)#\(file.id)#\(thumbnailURL?.path ?? "")#\(localURL?.path ?? "")#\(cacheGrade.rawValue)"
        ) {
            thumbnail = nil
            await loadThumbnail()
            await loadDuration()
        }
    }

    private func loadThumbnail() async {
        let cacheKey = "\(cameraID)#\(file.id)#grid" as NSString
        if let cached = MediaCellThumbnailCache.shared.object(forKey: cacheKey) {
            thumbnail = cached
            return
        }
        func present(_ image: UIImage) {
            guard !Task.isCancelled else { return }
            MediaCellThumbnailCache.shared.setObject(image, forKey: cacheKey)
            thumbnail = image
        }
        if let thumbnailURL,
            let image = await MediaCellImageLoader.shared.downsampled(
                at: thumbnailURL, maxPixelSize: 640)
        {
            present(image)
            return
        }
        if isPhoto, isDownloaded, let localURL,
            let image = await MediaCellImageLoader.shared.downsampled(
                at: localURL, maxPixelSize: 640)
        {
            present(image)
            return
        }
        await model.session.ensureThumbnail(for: file)
        if let cachedURL = model.session.thumbnailURL(for: file),
            let image = await MediaCellImageLoader.shared.downsampled(
                at: cachedURL, maxPixelSize: 640)
        {
            present(image)
            return
        }
        guard isDownloaded, !isPhoto, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let cgImage = try? await generator.image(at: time).image {
            present(UIImage(cgImage: cgImage))
        }
    }

    private func loadDuration() async {
        guard !Task.isCancelled, !isPhoto else { return }
        if file.durationSeconds > 0 {
            onDuration(MediaClipFormatting.durationLabel(seconds: file.durationSeconds))
            return
        }
        guard isDownloaded, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration), !Task.isCancelled, duration.isNumeric,
            duration.seconds > 0
        {
            onDuration(MediaClipFormatting.durationLabel(seconds: Int(duration.seconds)))
        }
    }
}

/// The shell's cover pages over the cameras and pair pages. The live monitor presents
/// `MediaLibraryView` / `SettingsRootView` over itself (`LiveViewScreen`).
struct AppPanelHost: View {
    let cover: ShellModel.Cover
    @Environment(\.monitorWindowGeometry) private var windowGeometry

    var body: some View {
        GeometryReader { proxy in
            let safeArea = OperatorPanelMetrics.standalonePanelSafeArea(
                from: OperatorPanelMetrics.resolvedDeviceSafeArea(
                    proxy.safeAreaInsets, window: windowGeometry.safeArea))
            switch cover {
            case .settings: SettingsRootView(safeArea: safeArea)
            case .media: MediaLibraryView(safeArea: safeArea)
            }
        }
    }
}

typealias MediaLibraryStubView = MediaLibraryView

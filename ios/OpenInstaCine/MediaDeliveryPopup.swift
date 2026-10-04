import MonitorPresentation
import MonitorUI
import OpenCineFrameIO
import OpenPocketViewCore
import SwiftUI

struct MediaDeliveryPopupOverlay: View {
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
    var onDismiss: () -> Void
    @Environment(\.monitorWindowGeometry) private var windowGeometry

    var body: some View {
        GeometryReader { geo in
            let safeArea = OperatorPanelMetrics.resolvedDeviceSafeArea(
                geo.safeAreaInsets, window: windowGeometry.safeArea)
            let cap = max(
                0,
                min(
                    geo.size.height * 0.86,
                    geo.size.height - safeArea.top - safeArea.bottom - 20))
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                MediaDeliveryPopup(
                    files: files,
                    preferredDestination: preferredDestination,
                    maxCardHeight: cap,
                    onClose: onDismiss
                )
                .padding(.leading, safeArea.leading + 12)
                .padding(.trailing, safeArea.trailing + 12)
                .padding(.bottom, safeArea.bottom + 10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

struct MediaDeliveryPopup: View {
    let files: [MediaFile]
    var preferredDestination: MediaDeliveryDestination? = nil
    var maxCardHeight: CGFloat = MediaDeliveryChrome.maxCardHeight
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var step: DeliveryStep
    @State private var destination: MediaDeliveryDestination?
    @State private var configuration = MediaDeliveryConfiguration()
    @State private var shareAction: MediaDeliveryPostExportAction = .systemShare
    @State private var statusMessage: String?
    @State private var frameioListing: FrameioProjectListing?
    @State private var frameioProjectsLoading = false
    @State private var frameioProjectsError: String?
    @State private var selectedFrameioProjectID: String?
    @State private var showCreateProjectAlert = false
    @State private var newProjectName = ""
    @State private var showFrameioHopConfirm = false
    @State private var isHoppingForFrameio = false
    @State private var popupHopToken: FrameioInternetHop.Token?
    @State private var popupHopTask: Task<Void, Never>?
    @State private var onCameraAP = false

    private enum DeliveryStep { case destination, options }

    init(
        files: [MediaFile],
        preferredDestination: MediaDeliveryDestination? = nil,
        maxCardHeight: CGFloat = MediaDeliveryChrome.maxCardHeight,
        onClose: @escaping () -> Void
    ) {
        self.files = files
        self.preferredDestination = preferredDestination
        self.maxCardHeight = maxCardHeight
        self.onClose = onClose
        _destination = State(initialValue: preferredDestination)
        _step = State(initialValue: preferredDestination == nil ? .destination : .options)
    }

    private var session: CameraSession { model.session }
    private var lutAvailable: Bool {
        model.assist.playbackEffects.lutDimension >= 2 || model.assist.effects.lutDimension >= 2
    }
    private var cached: [MediaFile] { files.filter { session.isDownloaded($0) } }
    private var isConnected: Bool {
        if case .live = session.phase { return true }
        return false
    }
    private var selectedFrameioProject: FrameioProject? {
        guard let listing = frameioListing, let id = selectedFrameioProjectID else { return nil }
        return listing.projects.first { $0.id == id }
    }
    private var uploadableFrameioProjects: [FrameioProject] {
        frameioListing?.projects.filter { $0.rootFolderID != nil } ?? []
    }
    private var frameioHopGateActive: Bool { destination == .frameio && onCameraAP }
    private var frameioProjectReady: Bool {
        guard destination == .frameio else { return true }
        guard model.isFrameioConnected else { return false }
        if selectedFrameioProject?.rootFolderID != nil { return true }
        if FrameioDestination.loaded != nil { return true }
        return model.isOnCameraAccessPoint
    }
    private var convertLogAvailable: Bool {
        MediaDelivery.convertLogAvailable(
            files: files,
            shotColors: files.map { session.shotColor(for: $0) })
    }
    private var previewTransform: LogColorTransform? {
        configuration.convertLog ? configuration.logTransform : nil
    }
    private var convertLogBinding: Binding<Bool> {
        Binding(
            get: { configuration.convertLog },
            set: { on in
                configuration.convertLog = on
                if on { configuration.bakeLUT = false }
            })
    }
    private var bakeLUTBinding: Binding<Bool> {
        Binding(
            get: { configuration.bakeLUT },
            set: { on in
                configuration.bakeLUT = on
                if on { configuration.convertLog = false }
            })
    }
    private var canContinue: Bool {
        destination != nil
            && (!cached.isEmpty || (isConnected && !files.isEmpty))
            && !(configuration.bakeLUT && !lutAvailable)
            && !(configuration.convertLog && !convertLogAvailable)
            && !(destination == .frameio && !frameioProjectReady)
    }

    var body: some View {
        MonitorMediaDeliveryPanel(value: panelValue, maxCardHeight: maxCardHeight,
            action: handlePanelAction) { id in
                if let candidate = MediaDeliveryDestination(rawValue: id) {
                    destinationIcon(candidate)
                }
            }
        .onAppear {
            if let firstLog = files.filter({ $0.kind == .video })
                .compactMap({ session.shotColor(for: $0) })
                .compactMap({ LogColorTransform.converting(from: $0) }).first
            {
                configuration.logTransform = firstLog
            }
            if !lutAvailable { configuration.bakeLUT = false }
            if !convertLogAvailable { configuration.convertLog = false }
            if let saved = FrameioDestination.loaded {
                selectedFrameioProjectID = saved.projectID
            }
            onCameraAP = model.isOnCameraAccessPoint
        }
        .onDisappear { finishPopupHop() }
        .task(id: step == .options) {
            guard step == .options else { return }
            while !Task.isCancelled {
                onCameraAP = model.isOnCameraAccessPoint
                if destination == .frameio, model.isFrameioConfigured, model.isFrameioConnected,
                    !onCameraAP, frameioListing == nil, !frameioProjectsLoading,
                    frameioProjectsError == nil
                {
                    await loadFrameioProjects()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("New Frame.io project", isPresented: $showCreateProjectAlert) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { newProjectName = "" }
            Button("Create") {
                let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                newProjectName = ""
                guard !name.isEmpty else { return }
                Task { await createFrameioProject(named: name) }
            }
            .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Creates a blank project in your workspace.")
        }
        .alert("Leave camera Wi‑Fi?", isPresented: $showFrameioHopConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Hop") { startFrameioHop() }
        } message: {
            Text(
                "We'll hop to home Wi‑Fi or cellular so you can sign in and pick a project. The camera reconnects automatically when you're done."
            )
        }
    }

    private var panelValue: MonitorMediaDeliveryValue {
        typealias Value = MonitorMediaDeliveryValue
        var notices: [Value.Notice] = []
        if cached.count < files.count {
            notices.append(.init(isConnected
                ? "\(files.count - cached.count) on-camera clip(s) will be cached from the camera first."
                : "\(files.count - cached.count) on-camera clip(s) will be skipped; reconnect the camera to cache them."))
        }
        if destination == .frameio, !model.isFrameioConfigured {
            notices.append(.init("Frame.io isn't configured; add credentials in Settings → Storage.", accented: true))
        } else if destination == .frameio, step == .options,
            let name = selectedFrameioProject?.name ?? FrameioDestination.loaded?.projectName {
            notices.append(.init("Project: \(name)"))
        }
        let service: Value.Service?
        if destination != .frameio { service = nil }
        else if frameioHopGateActive {
            let message = FrameioDestination.loaded.map {
                "Frame.io needs the internet. Hop off the camera's Wi-Fi to pick a project (currently “\($0.projectName)”) and upload; the camera reconnects automatically when you're done."
            } ?? "Frame.io needs the internet. Hop off the camera's Wi-Fi to sign in and pick a project; the camera reconnects automatically when you're done."
            service = .internetGate(heading: "FRAME.IO", message: message, busy: isHoppingForFrameio)
        } else {
            service = .projects(heading: "PROJECT", help: "Upload destination in your Frame.io workspace.",
                signInNotice: model.isFrameioConnected ? nil : "Sign in to Frame.io from Settings → Storage to upload.",
                loading: frameioProjectsLoading, error: frameioProjectsError,
                choices: frameioListing == nil ? nil : uploadableFrameioProjects.map { .init(id: $0.id, label: $0.name) },
                selectedID: selectedFrameioProjectID)
        }
        let export: Value.Export? = frameioHopGateActive ? nil : .init(
            filename: files.count == 1 ? files.first.map {
                MediaDelivery.filename(for: $0, configuration: configuration, transform: previewTransform)
            } : nil,
            convertLog: .init(MediaDeliveryCopy.convertLog,
                help: convertLogAvailable ? MediaDeliveryCopy.convertLogHelp : MediaDeliveryCopy.convertLogHelpUnavailable,
                isOn: configuration.convertLog, enabled: convertLogAvailable),
            outputCurve: configuration.convertLog ? .init(MediaDeliveryCopy.convertLogDestination,
                options: LogColorTransform.allCases.map { .init(id: $0.rawValue, label: $0.destination.label) },
                selectedID: configuration.logTransform.rawValue) : nil,
            bakeLUT: .init(MediaDeliveryCopy.bakeLUT,
                help: lutAvailable ? MediaDeliveryCopy.bakeLUTHelp(statusLabel: model.assist.lutStatusLabel) : MediaDeliveryCopy.bakeLUTHelpUnavailable,
                isOn: configuration.bakeLUT, enabled: lutAvailable),
            bakeExposure: configuration.bakeLUT ? .init(MediaDeliveryCopy.bakeExposure,
                help: MediaDeliveryCopy.bakeExposureHelp, isOn: configuration.bakeLUTExposure, enabled: lutAvailable) : nil,
            format: configuration.bakeLUT || configuration.convertLog || destination == .nativeShare
                ? .init("Format", help: "MOV preserves quality; MP4 is more widely compatible.",
                    options: MediaExportFormat.allCases.map { .init(id: $0.rawValue, label: $0.label) },
                    selectedID: configuration.exportFormat.rawValue) : nil,
            includeMetadata: .init("Include metadata", help: "Filename, capture date, and size (best-effort JSON sidecar).",
                isOn: configuration.includeMetadata),
            reupload: destination == .frameio ? .init("Re-upload already uploaded",
                help: "Skip clips already on Frame.io unless enabled.", isOn: configuration.forceFrameioReupload) : nil)
        let footer: Value.Footer? = step == .options && !frameioHopGateActive ? .init(
            summary: exportSummary,
            postExport: destination == .nativeShare ? .init("", options: [
                .init(id: MediaDeliveryPostExportAction.systemShare.rawValue, label: "Share"),
                .init(id: MediaDeliveryPostExportAction.saveToPhotos.rawValue, label: "Save to Photos")
            ], selectedID: shareAction.rawValue) : nil,
            actionTitle: actionTitle, enabled: canContinue) : nil
        return .init(step: step == .destination ? .destination : .options,
            title: destination?.title ?? "Share", selectionLabel: "\(files.count) clip\(files.count == 1 ? "" : "s")",
            notices: notices, destinations: MediaDeliveryDestination.allCases.map { candidate in
                .init(id: candidate.rawValue, title: candidate.title,
                    subtitle: candidate == .frameio && model.isFrameioConfigured && !model.isFrameioConnected
                        ? "Sign in from Settings → Storage first." : candidate.subtitle,
                    enabled: isDestinationEnabled(candidate))
            }, upcoming: ["Google Drive", "Dropbox", "NAS (SMB)", "LucidLink", "Backblaze B2", "Vimeo Review"],
            service: service, export: export, footer: footer, status: statusMessage)
    }

    private func handlePanelAction(_ action: MonitorMediaDeliveryValue.Action) {
        switch action {
        case .close: closePopup()
        case .back: step = .destination
        case .begin: if canContinue { beginDelivery() }
        case .hopToInternet: showFrameioHopConfirm = true
        case .retryProjects: Task { await loadFrameioProjects() }
        case .createProject: newProjectName = ""; showCreateProjectAlert = true
        case .destination(let id):
            guard let candidate = MediaDeliveryDestination(rawValue: id), isDestinationEnabled(candidate) else { return }
            destination = candidate; step = .options
            if candidate == .frameio { Task { await loadFrameioProjects() } }
        case .option(let option, let on):
            switch option {
            case .convertLog: convertLogBinding.wrappedValue = on
            case .bakeLUT: bakeLUTBinding.wrappedValue = on
            case .bakeExposure: configuration.bakeLUTExposure = on
            case .includeMetadata: configuration.includeMetadata = on
            case .reupload: configuration.forceFrameioReupload = on
            }
        case .selection(let selection, let id):
            switch selection {
            case .outputCurve:
                if let transform = LogColorTransform(rawValue: id) { configuration.logTransform = transform }
            case .format:
                if let format = MediaExportFormat(rawValue: id) { configuration.exportFormat = format }
            case .postExport:
                if let action = MediaDeliveryPostExportAction(rawValue: id) { shareAction = action }
            case .project:
                if let project = uploadableFrameioProjects.first(where: { $0.id == id }) { selectFrameioProject(project) }
            }
        }
    }

    @ViewBuilder
    private func destinationIcon(_ candidate: MediaDeliveryDestination) -> some View {
        switch candidate {
        case .nativeShare:
            OpcIcon.share
                .frame(width: 18, height: 18)
                .foregroundStyle(LiveDesign.text)
        case .frameio:
            FrameioMark()
                .foregroundStyle(model.isFrameioConfigured ? LiveDesign.text : LiveDesign.faint)
        }
    }

    private func isDestinationEnabled(_ candidate: MediaDeliveryDestination) -> Bool {
        let hasDeliverable = !cached.isEmpty || (isConnected && !files.isEmpty)
        switch candidate {
        case .nativeShare: return hasDeliverable
        case .frameio:
            return model.isFrameioConfigured && model.isFrameioConnected && hasDeliverable
        }
    }

    private var exportSummary: String {
        let known = files.filter { $0.sizeBytes > 0 }
        let bytes = known.reduce(UInt64(0)) { total, file in
            let sum = total.addingReportingOverflow(file.sizeBytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes), countStyle: .file)
        let sizeLabel =
            known.isEmpty
            ? "Size unavailable" : known.count == files.count ? size : "At least \(size)"
        let mode =
            configuration.convertLog
            ? configuration.logTransform.destination.label
            : configuration.bakeLUT ? "LUT baked" : "Camera original"
        return "\(files.count) \(files.count == 1 ? "clip" : "clips") · \(sizeLabel) · \(mode)"
    }

    private var actionTitle: String {
        switch destination {
        case .nativeShare:
            shareAction == .saveToPhotos ? "Save to Photos" : "Share"
        case .frameio:
            destination?.actionTitle ?? "Upload"
        case .none:
            "Continue"
        }
    }

    private func beginDelivery() {
        guard let destination else { return }
        let internetHopToken: FrameioInternetHop.Token?
        if destination == .frameio {
            // The accepted upload owns restoration, including preflight failure.
            internetHopToken = popupHopToken.map { model.transferInternetHop($0) ?? $0 }
            popupHopToken = nil
            popupHopTask?.cancel()
            popupHopTask = nil
        } else {
            internetHopToken = nil
            finishPopupHop()
        }
        let request = MediaDeliveryBeginRequest(
            files: files,
            destination: destination,
            configuration: configuration,
            postExportAction: shareAction,
            internetHopToken: internetHopToken)
        onClose()
        model.delivery.begin(request, model: model)
    }

    private func closePopup() {
        finishPopupHop()
        onClose()
    }

    private func finishPopupHop() {
        popupHopTask?.cancel()
        popupHopTask = nil
        guard let token = popupHopToken else { return }
        popupHopToken = nil
        model.endInternetHop(token)
    }

    private func startFrameioHop() {
        isHoppingForFrameio = true
        popupHopTask?.cancel()
        let token = model.beginInternetHop()
        popupHopToken = token
        popupHopTask = Task {
            let online = await model.waitForInternetPath(timeoutSeconds: 30, token: token)
            guard !Task.isCancelled, popupHopToken == token, model.internetHop.owns(token) else {
                return
            }
            isHoppingForFrameio = false
            if online {
                await loadFrameioProjects(hop: token)
            } else {
                frameioProjectsError =
                    "Couldn't reach the internet after leaving the camera's Wi‑Fi. Check cellular or home Wi‑Fi."
            }
        }
    }

    private func loadFrameioProjects(hop: FrameioInternetHop.Token? = nil) async {
        guard !model.isOnCameraAccessPoint else { return }
        frameioProjectsLoading = true
        frameioProjectsError = nil
        defer {
            if hop == nil || hop.map({ model.internetHop.owns($0) }) == true {
                frameioProjectsLoading = false
            }
        }
        do {
            let listing = try await model.loadFrameioProjectListing()
            guard !Task.isCancelled,
                hop == nil || hop.map({ model.internetHop.owns($0) }) == true
            else { return }
            frameioListing = listing
            if selectedFrameioProjectID == nil {
                selectedFrameioProjectID =
                    FrameioDestination.loaded?.projectID ?? listing.projects.first?.id
            }
            if let project = selectedFrameioProject {
                selectFrameioProject(project)
            }
        } catch {
            guard !Task.isCancelled,
                hop == nil || hop.map({ model.internetHop.owns($0) }) == true
            else { return }
            frameioProjectsError = error.localizedDescription
        }
    }

    private func selectFrameioProject(_ project: FrameioProject) {
        selectedFrameioProjectID = project.id
        if let listing = frameioListing {
            model.persistFrameioDestination(
                project: project, accountID: listing.accountID, workspaceID: listing.workspaceID)
        }
    }

    private func createFrameioProject(named name: String) async {
        guard let listing = frameioListing else { return }
        do {
            let project = try await model.createFrameioProject(
                name: name, accountID: listing.accountID, workspaceID: listing.workspaceID)
            frameioListing?.projects.insert(project, at: 0)
            selectFrameioProject(project)
        } catch {
            frameioProjectsError = error.localizedDescription
        }
    }
}

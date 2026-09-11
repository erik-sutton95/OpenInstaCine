import MonitorContracts
import OpenPocketViewCore
import XCTest

@testable import MonitorUI

@MainActor
final class CameraBackendFacadeTests: XCTestCase {
    func testUnverifiedControlsNeverReachAdapterOrInventStatus() async {
        let backend = SpyBackend(capabilities: [.liveVideo])
        let session = CameraSession(backend: backend)
        session.activateBackend()
        session.phase = .live
        session.pressShutter()
        session.setISO(.iso800)
        session.setWhiteBalanceCustom(kelvin: 5600, tint: 4)
        session.setVideoFormat(resolution: .p4K, frameRate: .fps25)
        session.setZoom(2)
        session.recenterGimbal()
        session.handleFeedTap(at: .init(x: 0.3, y: 0.4))
        await Task.yield()
        XCTAssertTrue(backend.intents.isEmpty)
        XCTAssertFalse(session.status.isRecording)
        XCTAssertEqual(session.status.iso, -1)
        XCTAssertNil(session.status.whiteBalance)
        XCTAssertNil(session.status.videoFormat)
        XCTAssertNotNil(session.controlNote)
        session.disconnect()
    }

    func testSupportedControlUsesSemanticIntentAndWaitsForCameraTruth() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .recording, .exposure])
        let session = CameraSession(backend: backend)
        session.activateBackend()
        session.phase = .live
        let sent = expectation(description: "semantic intent reaches selected backend")
        backend.didApply = { sent.fulfill() }
        session.pressShutter()
        await fulfillment(of: [sent], timeout: 1)
        XCTAssertEqual(backend.intents, [.record(start: true)])
        XCTAssertFalse(session.status.isRecording, "A successful write is not camera telemetry")
        backend.eventHandler?(
            .status(
                CameraStatusSnapshot(
                    recording: true, recordedSeconds: 12,
                    parameters: [.iso: .number(800)])))
        XCTAssertTrue(session.status.isRecording)
        XCTAssertEqual(session.status.recordElapsedSec, 12)
        XCTAssertEqual(session.status.iso, 800)
        XCTAssertEqual(session.status.isoIndex, .iso800)
        session.disconnect()
    }

    func testPhysicalUnitsCrossExposureBoundary() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .exposure])
        let session = CameraSession(backend: backend)
        session.activateBackend()
        session.phase = .live
        let sent = expectation(description: "three exposure intents")
        sent.expectedFulfillmentCount = 3
        backend.didApply = { sent.fulfill() }
        session.setISO(.iso1600)
        session.setShutterDenom(50)
        session.setEv(.init(thirds: 2))
        await fulfillment(of: [sent], timeout: 1)
        XCTAssertEqual(
            backend.intents,
            [
                .parameter(.iso, .number(1600)),
                .parameter(.shutterSeconds, .number(0.02)),
                .parameter(.exposureCompensationStops, .number(2.0 / 3.0)),
            ])
        session.disconnect()
    }

    func testInterfaceLockBlocksCameraWrites() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .recording, .exposure])
        let session = CameraSession(backend: backend)
        session.activateBackend()
        session.phase = .live
        session.isLocked = true
        session.pressShutter()
        session.setISO(.iso800)
        await Task.yield()
        XCTAssertTrue(backend.intents.isEmpty)
        session.disconnect()
    }

    func testOpeningUnavailableLibraryKeepsLiveTransportAndUnknownTelemetry() async {
        let backend = SpyBackend(capabilities: [.liveVideo])
        let session = CameraSession(backend: backend)
        session.activateBackend()
        session.phase = .live
        session.beginMediaBrowse()
        await session.refreshMedia()
        XCTAssertEqual(session.phase, .live)
        XCTAssertTrue(session.isBrowsingMedia)
        XCTAssertEqual(backend.disconnectCalls, 0)
        XCTAssertEqual(backend.listCalls, 0)
        XCTAssertNotNil(session.mediaNote)
        session.endMediaBrowse()
        XCTAssertEqual(backend.disconnectCalls, 0)
        session.disconnect()
    }

    func testSelectingAnotherCameraClearsPreviousCatalogAndControlContext() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .cameraMedia])
        let session = CameraSession(backend: backend)
        let first = FoundCamera(id: UUID(), name: "First", model: CameraModel(name: "Test"))
        let second = FoundCamera(id: UUID(), name: "Second", model: CameraModel(name: "Test"))
        session.connect(first)
        await Task.yield()
        session.mediaFiles = [MediaFile(path: "first/clip.mp4", thumbPath: "first/thumb.jpg")]
        session.mediaAssets = [
            "first/clip.mp4": .init(id: "opaque-first", filename: "clip.mp4", canDelete: true)
        ]
        session.mediaDownloadProgress = ["first/clip.mp4": 0.4]
        session.connect(second)
        XCTAssertTrue(session.mediaFiles.isEmpty)
        XCTAssertTrue(session.mediaAssets.isEmpty)
        XCTAssertTrue(session.mediaDownloadProgress.isEmpty)
        XCTAssertEqual(session.mediaCameraID, second.id.uuidString)
        session.disconnect()
    }

    func testLateCatalogCannotPublishIntoAnotherCamera() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .cameraMedia])
        let session = CameraSession(backend: backend)
        let entered = expectation(description: "first catalog is awaiting backend")
        var reply: CheckedContinuation<[CameraMediaAsset], Error>?
        backend.listResponse = {
            try await withCheckedThrowingContinuation { continuation in
                reply = continuation
                entered.fulfill()
            }
        }
        session.connect(FoundCamera(id: UUID(), name: "First", model: CameraModel(name: "Test")))
        await Task.yield()
        session.phase = .live
        let oldRefresh = Task { await session.refreshMedia() }
        await fulfillment(of: [entered], timeout: 1)
        let second = FoundCamera(id: UUID(), name: "Second", model: CameraModel(name: "Test"))
        session.connect(second)
        reply?.resume(returning: [.init(id: "old-camera-asset", filename: "old.mp4")])
        await oldRefresh.value
        XCTAssertTrue(session.mediaFiles.isEmpty)
        XCTAssertTrue(session.mediaAssets.isEmpty)
        XCTAssertEqual(session.mediaCameraID, second.id.uuidString)
        session.disconnect()
    }

    func testFailedDeletionKeepsCatalogAndReturnsFalse() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .cameraMedia])
        backend.deleteError = CameraBackendError.unavailable("Deletion test failure")
        let session = CameraSession(backend: backend)
        session.phase = .live
        let file = MediaFile(path: "test/clip.mp4", thumbPath: "test/thumb.jpg")
        session.mediaFiles = [file]
        session.mediaAssets[file.path] = .init(
            id: "opaque-asset", filename: "clip.mp4", canDelete: true)
        let succeeded = await session.deleteMediaFiles([file])
        XCTAssertFalse(succeeded)
        XCTAssertEqual(backend.deleteCalls, 1)
        XCTAssertEqual(session.mediaFiles.map(\.path), [file.path])
        XCTAssertEqual(session.mediaAssets[file.path]?.id, "opaque-asset")
        XCTAssertNotNil(session.mediaNote)
        session.disconnect()
    }

    func testUnavailableOrReadOnlyDeletionNeverReachesCamera() async {
        let backend = SpyBackend(capabilities: [.liveVideo, .cameraMedia])
        let session = CameraSession(backend: backend)
        session.phase = .live
        let file = MediaFile(path: "test/clip.mp4", thumbPath: "test/thumb.jpg")
        session.mediaFiles = [file]
        session.mediaAssets[file.path] = .init(
            id: "read-only", filename: "clip.mp4", canDelete: false)
        let succeeded = await session.deleteMediaFiles([file])
        XCTAssertFalse(succeeded)
        XCTAssertEqual(backend.deleteCalls, 0)
        XCTAssertEqual(session.mediaFiles.map(\.path), [file.path])
        session.disconnect()
    }

    func testCapturePanelsDeclareTheirRequiredCameraCapabilities() {
        XCTAssertEqual(CaptureSheet.iso.requiredCapability, .exposure)
        XCTAssertEqual(CaptureSheet.shutter.requiredCapability, .exposure)
        XCTAssertEqual(CaptureSheet.exposure.requiredCapability, .exposure)
        XCTAssertEqual(CaptureSheet.wb.requiredCapability, .whiteBalance)
        XCTAssertEqual(CaptureSheet.focus.requiredCapability, .focus)
        XCTAssertEqual(CaptureSheet.audio.requiredCapability, .liveAudio)
        XCTAssertEqual(CaptureSheet.resolution.requiredCapability, .captureFormat)
        XCTAssertEqual(CaptureSheet.mode.requiredCapability, .captureFormat)
        XCTAssertEqual(CaptureSheet.color.requiredCapability, .captureFormat)
    }

    func testLocalAnglePreferenceDoesNotInventUnknownShutterTelemetry() {
        var status = CameraStatus()
        XCTAssertEqual(
            CaptureAvailabilityCopy.shutterReadout(
                status: status, usesAngle: true, angleDegrees: 180), "—")
        status.shutterDenom = 50
        XCTAssertEqual(
            CaptureAvailabilityCopy.shutterReadout(
                status: status, usesAngle: true, angleDegrees: 180), "—")
        XCTAssertEqual(
            CaptureAvailabilityCopy.shutterReadout(
                status: status, usesAngle: false, angleDegrees: 180), "1/50")
        status.fps = 25
        XCTAssertEqual(
            CaptureAvailabilityCopy.shutterReadout(
                status: status, usesAngle: true, angleDegrees: 180), "180°")
    }

    func testUnavailableAudioNeverAnnouncesSilentTelemetry() {
        let panel = AudioAssist.meter(levels: .silent, sensitivity: "Stereo", available: false)
        XCTAssertEqual(panel.accessibilityValue, AudioAssist.unavailableCopy)
        XCTAssertFalse(panel.accessibilityValue.contains("silent"))
    }

    func testReplayAndHeldFramesDoNotClaimActiveCameraTransport() {
        let replay = MonitorTransportPresentation(
            phase: .live, sourceLabel: "Local replay", cameraNetwork: false, holdsMonitor: false,
            recovery: .idle)
        XCTAssertEqual(replay.title, "Local replay")
        XCTAssertEqual(replay.transport, "Local replay")
        XCTAssertFalse(replay.hasActiveCameraLink)
        let held = MonitorTransportPresentation(
            phase: .live, sourceLabel: nil, cameraNetwork: true, holdsMonitor: true, recovery: .idle
        )
        XCTAssertEqual(held.title, "Picture held")
        XCTAssertEqual(held.transport, "No active camera link")
        XCTAssertFalse(held.hasActiveCameraLink)
        let recovering = MonitorTransportPresentation(
            phase: .openingDatalink, sourceLabel: nil, cameraNetwork: true, holdsMonitor: true,
            recovery: .retrying(attempt: 1, maxAttempts: 3))
        XCTAssertFalse(recovering.hasActiveCameraLink)
        XCTAssertEqual(recovering.transport, "No active camera link")
    }

    func testLunaWiFiPreviewDoesNotClaimBluetoothRemainsConnected() {
        let live = MonitorTransportPresentation(
            phase: .live, sourceLabel: nil, cameraNetwork: true, holdsMonitor: false,
            recovery: .idle)
        XCTAssertTrue(live.hasActiveCameraLink)
        XCTAssertEqual(live.transport, "Wi-Fi video")
        let setup = MonitorTransportPresentation(
            phase: .awaitingApproval, sourceLabel: nil, cameraNetwork: false, holdsMonitor: false,
            recovery: .idle)
        XCTAssertFalse(setup.hasActiveCameraLink)
        XCTAssertEqual(setup.transport, "Bluetooth setup")
    }

    func testDiscardedStateCandidateCannotStealActiveBackendEvents() {
        let backend = SpyBackend(capabilities: [.liveVideo])
        let retained = CameraSession(backend: backend)
        retained.activateBackend()
        _ = CameraSession(backend: backend)
        backend.eventHandler?(
            .information(
                .init(
                    model: "Retained source", sourceLabel: "ACTIVE SOURCE", previewTransfer: .rec709
                )))
        XCTAssertEqual(retained.sourceLabel, "ACTIVE SOURCE")
        XCTAssertEqual(retained.monitorTransfer, .rec709)
        retained.disconnect()
    }

    func testPreviewInformationNeverBecomesCaptureFormat() {
        let backend = SpyBackend(capabilities: [.liveVideo])
        let session = CameraSession(backend: backend)
        session.activateBackend()
        backend.eventHandler?(
            .information(
                .init(
                    model: "Test source", firmware: "1.0", sourceLabel: "Local replay",
                    previewTransfer: .rec709)))
        XCTAssertEqual(session.status.firmware, "1.0")
        XCTAssertEqual(session.sourceLabel, "Local replay")
        XCTAssertEqual(session.monitorTransfer, .rec709)
        XCTAssertEqual(session.status.fps, 0)
        XCTAssertNil(session.status.videoFormat)
        XCTAssertNil(session.status.colorMode)
        session.disconnect()
        XCTAssertNil(session.sourceLabel)
    }
}

@MainActor
private final class SpyBackend: CameraBackend {
    let capabilities: CameraCapabilities
    var eventHandler: ((CameraBackendEvent) -> Void)?
    var isOnCameraNetwork = false
    var intents: [CameraControlIntent] = []
    var didApply: (() -> Void)?
    var disconnectCalls = 0
    var listCalls = 0
    var deleteCalls = 0
    var deleteError: Error?
    var listResponse: (() async throws -> [CameraMediaAsset])?
    init(capabilities: CameraCapabilities) { self.capabilities = capabilities }
    func startScan() async throws {}
    func connect(to camera: MonitorCamera) async throws { eventHandler?(.phase(.streaming)) }
    func disconnect() { disconnectCalls += 1 }
    func forget(cameraID: UUID) {}
    func leaveCameraNetwork() {}
    func rejoinCameraNetwork() async throws {}
    func apply(_ intent: CameraControlIntent) async throws {
        intents.append(intent)
        didApply?()
    }
    func deleteMedia(_ asset: CameraMediaAsset) async throws {
        deleteCalls += 1
        if let deleteError { throw deleteError }
    }
    func listMedia() async throws -> [CameraMediaAsset] {
        listCalls += 1
        if let listResponse { return try await listResponse() }
        return []
    }
}

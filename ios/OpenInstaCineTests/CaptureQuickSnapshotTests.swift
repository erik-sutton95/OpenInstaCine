import MonitorPresentation
import OpenCineCameraControls
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

final class CaptureQuickSnapshotTests: XCTestCase {
    func testRecordingConfirmationIsBoundToOriginalCameraState() {
        let request = RecordConfirmationContext(
            mode: 1, recording: false, locked: false, busy: false, phase: .live)
        XCTAssertTrue(request.canConfirm)
        let changedStates = [
            RecordConfirmationContext(
                mode: 0, recording: false, locked: false, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: true, locked: false, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: true, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: false, busy: true, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: false, busy: false, phase: .idle),
        ]
        // Mirrors the LiveRecordButton confirm guard: `pending == current && current.canConfirm`.
        let confirms = { (current: RecordConfirmationContext) in
            request == current && current.canConfirm
        }
        XCTAssertTrue(confirms(request))
        for changed in changedStates {
            XCTAssertNotEqual(
                changed, request, "every captured field must bind the confirmation: \(changed)")
            XCTAssertFalse(confirms(changed), "stale confirmation must not fire after \(changed)")
        }
        XCTAssertFalse(
            RecordConfirmationContext(
                mode: 1, recording: nil, locked: false, busy: false, phase: .live
            ).canConfirm, "unknown recording has no explicit target to confirm")
        for photo in [0x05, 0x17] {
            XCTAssertFalse(
                RecordConfirmationContext(
                    mode: photo, recording: false, locked: false, busy: false, phase: .live
                ).canConfirm)
        }
    }

    func testHeldFocusIncludesTheSameTrackingChoicesAndNativeSelectionAsTap() throws {
        var status = CameraStatus()
        for option in CaptureLists.focusOptions {
            status.focusMode = option.focusMode
            status.focusTrack = option.track
            let snapshot = try XCTUnwrap(
                CaptureQuickSnapshot.primary(
                    .focus, status: status, supportsFocusMode: true, focusOptions: CaptureLists.focusOptions))
            XCTAssertEqual(snapshot.options, ["AF-S", "AF-C", "Showcase"])
            XCTAssertEqual(snapshot.selection, CaptureLists.focusOption(from: status)?.chip)
            XCTAssertEqual(snapshot.options[snapshot.index], option.chip)
        }
    }

    func testFormatColorAndModeSnapshotsMatchTheFullPickerPrimaryDrum() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps24)
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24),
            VideoFormat(resolution: .p4K, frameRate: .fps30),
            VideoFormat(resolution: .p1080, frameRate: .fps24),
        ]
        let format = try XCTUnwrap(CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertEqual(format.options, ["24p", "30p"])
        XCTAssertEqual(format.selection, "24p")
        XCTAssertEqual(format.changedValue(translation: -56, current: format), "30p")
        XCTAssertNil(format.changedValue(translation: 0, current: format))

        status.availableVideoFormats = [VideoFormat(resolution: .p4K, frameRate: .fps24)]
        let narrowed = CaptureQuickSnapshot.primary(.resolution, status: status)
        XCTAssertNil(format.changedValue(translation: -56, current: narrowed))

        status.colorMode = .normal
        status.availableColorModes = [.normal, .hdr, .dLog]
        let color = try XCTUnwrap(CaptureQuickSnapshot.primary(.color, status: status, profile: LunaShellMapping.profile))
        XCTAssertEqual(color.options, ["Standard", "HDR", "D-Log"])
        XCTAssertEqual(color.selection, "Standard")
        XCTAssertEqual(color.changedValue(translation: -56, current: color), "HDR")

        status.availableColorModes = [.normal]
        let colorChanged = CaptureQuickSnapshot.primary(.color, status: status, profile: LunaShellMapping.profile)
        XCTAssertNil(color.changedValue(translation: -56, current: colorChanged))

        status.shootingMode = Int(ShootingMode.video.rawValue)
        let mode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status, profile: LunaShellMapping.profile))
        XCTAssertEqual(
            mode.options, CaptureLists.operatorShootingModes(from: status).map { $0.label(in: LunaShellMapping.profile) })
        XCTAssertFalse(mode.options.contains(ShootingMode.livePhoto.label(in: LunaShellMapping.profile)))
        XCTAssertEqual(mode.selection, "Video")
        XCTAssertNil(mode.changedValue(translation: 0, current: mode))
        XCTAssertEqual(mode.changedValue(translation: -56, current: mode), ShootingMode.timeLapse.label(in: LunaShellMapping.profile))

        status.shootingMode = Int(ShootingMode.photo.rawValue)
        let photo = CaptureQuickSnapshot.primary(.mode, status: status, profile: LunaShellMapping.profile)
        XCTAssertNil(mode.changedValue(translation: -56, current: photo))
        XCTAssertEqual(photo?.selection, "Photo")

        status.shootingMode = Int(ShootingMode.photoRawPocket3AndNano)
        let pocket3Photo = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status, profile: LunaShellMapping.profile))
        XCTAssertEqual(pocket3Photo.selection, "Photo")

        status.shootingMode = -1
        let unknown = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status, profile: LunaShellMapping.profile))
        XCTAssertEqual(unknown.selection, "")
        XCTAssertNil(unknown.changedValue(translation: 0, current: unknown))
    }

    func testLivePhotoUsesStillChromeAndHidesVideoColorAudio() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.livePhoto.rawValue)
        status.colorMode = .dLogM
        status.audioChannel = .stereo
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24)
        ]
        XCTAssertTrue(status.isPhoto)
        XCTAssertNil(CaptureQuickSnapshot.primary(.color, status: status, profile: LunaShellMapping.profile))
        XCTAssertNil(CaptureQuickSnapshot.primary(.audio, status: status))
        let format = try XCTUnwrap(CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertEqual(format.selection, "Photo")
        XCTAssertFalse(format.enabled)
        let mode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status, profile: LunaShellMapping.profile))
        XCTAssertTrue(mode.options.contains(ShootingMode.livePhoto.label(in: LunaShellMapping.profile)))
        XCTAssertEqual(mode.selection, ShootingMode.livePhoto.label(in: LunaShellMapping.profile))
        XCTAssertNil(mode.changedValue(translation: 0, current: mode))
        status.shootingMode = Int(ShootingMode.video.rawValue)
        let videoMode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status, profile: LunaShellMapping.profile))
        XCTAssertFalse(videoMode.options.contains(ShootingMode.livePhoto.label(in: LunaShellMapping.profile)))
    }
}

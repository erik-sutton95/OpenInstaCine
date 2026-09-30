import Insta360Protocol
import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

@MainActor
final class LunaShellMappingTests: XCTestCase {
    func testObservedRecordResolutionsMapToLabelledFormats() throws {
        let table = LunaShellMapping.formatTable(values: [52, 48, 24, 454])
        let labels = Set(table.keys.map(\.chipLabel))
        XCTAssertTrue(labels.contains("1080p · 25p"), "\(labels)")
        XCTAssertTrue(labels.contains("4K · 25p"), "\(labels)")
        XCTAssertTrue(labels.contains("4K · 30p"), "\(labels)")
        XCTAssertTrue(labels.contains(where: { $0.hasPrefix("3K 9:16") }), "\(labels)")
        // Round trip: the SET value for a shown format is the value the camera reported.
        let fourK25 = try XCTUnwrap(table.first { $0.key.chipLabel == "4K · 25p" })
        XCTAssertEqual(fourK25.value, 48)
    }

    func testColorAndModeRoundTrip() {
        for luna in [LunaColorMode.standard, .iLog, .dolbyVision] {
            XCTAssertEqual(
                LunaShellMapping.lunaColorMode(LunaShellMapping.colorMode(luna)), luna)
        }
        for mode in LunaShootingMode.allCases where mode != .pano {
            let shell = LunaShellMapping.shootingMode(mode)
            XCTAssertEqual(LunaShellMapping.lunaShootingMode(shell), mode)
        }
    }

    func testPreviewTransferFollowsColorRecovery() {
        XCTAssertEqual(LunaShellMapping.previewColorMode(recording: .iLog, recoveryOff: true), .iLog)
        XCTAssertEqual(LunaShellMapping.previewColorMode(recording: .iLog, recoveryOff: false), .normal)
        XCTAssertEqual(LunaShellMapping.previewColorMode(recording: .normal, recoveryOff: true), .normal)
    }

    func testFirmware1115GimbalModesAndSquareFormats() throws {
        for mode in GimbalMode.pickerOrder {
            XCTAssertEqual(LunaShellMapping.gimbalMode(LunaShellMapping.lunaGimbalMode(mode)), mode)
        }
        XCTAssertEqual(LunaShellMapping.lunaGimbalMode(.directionLock), .fpvVertical)
        XCTAssertNil(LunaShellMapping.gimbalMode(.lock))
        let table = LunaShellMapping.formatTable(values: LunaShellMapping.videoFormatValues)
        let square = try XCTUnwrap(table.first { $0.value == 120 })
        XCTAssertEqual(square.key.resolution, .p3K_1x1)
        XCTAssertEqual(square.key.chipLabel, "3K 1:1 · 25p")
        XCTAssertTrue(table.values.contains(443))
    }

    func testDeepTrackStreamStatesDriveTheBoxes() throws {
        func frame(state: UInt8, x: Float) throws -> LunaTrackFrame {
            var box = Data([0x0d]) + withUnsafeBytes(of: x.bitPattern.littleEndian) { Data($0) }
            box += Data([0x1d]) + withUnsafeBytes(of: Float(0.15).bitPattern.littleEndian) { Data($0) }
            box += Data([0x25]) + withUnsafeBytes(of: Float(0.27).bitPattern.littleEndian) { Data($0) }
            return try LunaTrackFrame(Data([0x10, state, 0x22, UInt8(box.count)]) + box)
        }
        let session = CameraSession(borrowing: HevcDecoder())
        session.applyTrackFrame(try frame(state: 5, x: 0.4))
        XCTAssertFalse(session.isTrackingActive, "idle before any lock is ignored")
        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        XCTAssertEqual(try XCTUnwrap(session.subjectBox).x, 0.4, accuracy: 0.001)
        session.applyTrackFrame(try frame(state: 3, x: 0.42))
        XCTAssertNil(session.subjectBox)
        XCTAssertEqual(try XCTUnwrap(session.searchBox).x, 0.42, accuracy: 0.001)
        XCTAssertTrue(session.isTrackingActive, "lost keeps tracking on so cancel stays available")
        XCTAssertEqual(
            FocusOverlayPolicy.resolve(
                tracking: session.isTracking, search: session.searchBox, subject: session.subjectBox),
            .search(try XCTUnwrap(session.searchBox)), "lost draws the white search box")
        session.applyTrackFrame(try frame(state: 2, x: 0.3))
        XCTAssertNotNil(session.subjectBox)
        session.applyTrackFrame(try frame(state: 5, x: 0.3))
        XCTAssertFalse(session.isTrackingActive, "idle after a lock ends tracking")
    }

    /// fw 1.1.15: option 93 values 1, 3, 6 are the official AF-S, AF-C, Product Showcase.
    func testAutofocusModesMapToFocusDrum() throws {
        XCTAssertEqual(CaptureLists.focusOptions.map(\.chip), ["AF-S", "AF-C", "Showcase"])
        for luna in LunaAFMode.allCases {
            XCTAssertEqual(LunaShellMapping.lunaAFMode(LunaShellMapping.focusOption(luna)), luna)
        }
        XCTAssertNil(LunaShellMapping.lunaAFMode(.subjectLock))
        XCTAssertNil(LunaShellMapping.lunaAFMode(.registeredPriority))

        // Reply types [93, 46] with 93 = 6 (Product Showcase), 46 = 0 (Matrix).
        let showcase = try LunaPhotographySettings(response: Data([0x08, 0x5D, 0x08, 0x2E, 0x12, 0x06,
                                                                  0xE8, 0x05, 0x06, 0xF0, 0x02, 0x00]))
        XCTAssertEqual(showcase.faceMetering, false)
        var status = CameraStatus()
        var pins = LunaControlPins()
        var table: [VideoFormat: UInt64] = [:]
        LunaShellMapping.apply(settings: showcase, to: &status, pins: &pins, table: &table)
        XCTAssertEqual(CaptureLists.focusOption(from: status), .productShowcase)

        // An optimistic AF-S pin holds until the camera reports it.
        pins.focus = CameraValuePin(.single, now: Date.timeIntervalSinceReferenceDate, settle: 3)
        LunaShellMapping.apply(settings: showcase, to: &status, pins: &pins, table: &table)
        XCTAssertEqual(CaptureLists.focusOption(from: status), .single)
        var single = showcase
        single.afMode = 1
        LunaShellMapping.apply(settings: single, to: &status, pins: &pins, table: &table)
        XCTAssertEqual(CaptureLists.focusOption(from: status), .single)
        XCTAssertNil(pins.focus)

        // Values the official app never offers (2 MACRO) blank the readout rather than guess.
        var macro = showcase
        macro.afMode = 2
        LunaShellMapping.apply(settings: macro, to: &status, pins: &pins, table: &table)
        XCTAssertNil(CaptureLists.focusOption(from: status))
    }

    func testHeadTrackReferenceFitsRateAndAcceleration() {
        XCTAssertNil(CameraSession.headTrackReference([], at: 1))
        // yaw = 5 + 30 t + 20 t² (rate 30 + 40 t, accel 40), still pitch, every 40 ms.
        let samples = (0..<7).map { i -> HeadTrackSample in
            let t = Double(i) * 0.04
            return HeadTrackSample(t: 10 + t, yaw: 5 + 30 * t + 20 * t * t, pitch: 3)
        }
        let head = CameraSession.headTrackReference(samples, at: 10.24 + 0.05)
        XCTAssertEqual(head?.yawRate ?? 0, 30 + 40 * 0.24, accuracy: 1e-6)
        XCTAssertEqual(head?.yawAccel ?? 0, 40, accuracy: 1e-6)
        XCTAssertEqual(head?.yaw ?? 0, 5 + 30 * 0.29 + 20 * 0.29 * 0.29, accuracy: 1e-6)
        XCTAssertEqual(head?.pitchRate ?? 1, 0, accuracy: 1e-9)
        // Two samples: a straight line. A stale head holds, with no rate to feed forward.
        let line = [HeadTrackSample(t: 1, yaw: 0, pitch: 0), HeadTrackSample(t: 1.04, yaw: 2, pitch: 0)]
        XCTAssertEqual(CameraSession.headTrackReference(line, at: 1.14)?.yaw ?? 0, 2 + 50 * 0.1, accuracy: 1e-6)
        XCTAssertEqual(CameraSession.headTrackReference(line, at: 9), HeadTrackReference(yaw: 2, pitch: 0))
    }

    func testTimeOfDayTimecode() {
        // 2026-09-30 08:51:10.54 UTC, Stockholm (UTC+2).
        let t = 1_790_758_270.54
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: t, timeZoneSeconds: 7200, fps: 25), "10:51:10:13")
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: t, timeZoneSeconds: 7200, fps: 30), "10:51:10:16")
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: t, timeZoneSeconds: 7200, fps: 50), "10:51:10:13")
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: t, timeZoneSeconds: 7200, fps: 120), "10:51:10:16")
        // Wraps at midnight, west of GMT too.
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: 86_399.99, timeZoneSeconds: 0, fps: 24), "23:59:59:23")
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: 3600, timeZoneSeconds: -7200, fps: 24), "23:00:00:00")
    }

    func testCameraNaming() {
        XCTAssertEqual(LunaCameraNames.title(advertised: "XBQFN7"), "Luna Ultra XBQFN7")
        XCTAssertEqual(LunaCameraNames.title(advertised: "Luna Ultra XBQFN7"), "Luna Ultra XBQFN7")
    }

    func testInsta360FilenameDates() {
        let file = MediaFile(
            path: "/storage_internal/DCIM/Camera01/VID_20260916_123456_00_001.mp4",
            thumbPath: "")
        XCTAssertEqual(file.filenameTimestamp, "20260916123456")
        XCTAssertEqual(MediaHTTP.proxyPaths(file).first?.hasSuffix(".lrv"), true)
    }

    func testProgrammedMovePathInterpolatesLegsAndCurve() throws {
        let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        let b = GimbalWaypoint(yawDeg: 40, pitchDeg: 10, zoom: 1)
        let c = GimbalWaypoint(yawDeg: 40, pitchDeg: 30, zoom: 1)
        var take = GimbalProgram(a: a, b: b, durationAB: 4, durationBC: 2)
        XCTAssertEqual(CameraSession.programDuration(take), 4)
        XCTAssertEqual(CameraSession.programPose(take, at: 1)?.yawDeg ?? .nan, 10, accuracy: 1e-9)
        XCTAssertEqual(CameraSession.programPose(take, at: 9), b)
        take.c = c
        take.smoothness = 0
        XCTAssertEqual(CameraSession.programDuration(take), 6)
        XCTAssertEqual(CameraSession.programPose(take, at: 5)?.pitchDeg ?? .nan, 20, accuracy: 1e-9)
        XCTAssertEqual(CameraSession.programPose(take, at: 6), c)
        // Smoothness rounds the B corner: the path no longer passes through B.
        take.smoothness = 1
        let corner = try XCTUnwrap(CameraSession.programPose(take, at: 4))
        XCTAssertGreaterThan(GimbalMoveEngine.angularDistance(corner, b), 1)
        XCTAssertEqual(CameraSession.programPose(take, at: 6), c)
    }
}

@MainActor
final class PictureEVMeterTests: XCTestCase {
    func testLearnsTheAutoExposurePlacementAndReadsManualAgainstIt() {
        let defaults = UserDefaults(suiteName: "PictureEVMeterTests")!
        defaults.removePersistentDomain(forName: "PictureEVMeterTests")
        let meter = PictureEVMeter(defaults: defaults)
        // Seeded: auto at EV 0 with the I-Log median 1.3 stops under grey reads 0.
        XCTAssertEqual(meter.stops(picture: -1.3, transfer: .ilog, evComp: nil, now: 0), 0, accuracy: 1e-9)
        // Auto at EV 0 in a scene the camera places at -0.8: the offset follows.
        var t = 0.0
        while t < 20 {
            t += 0.04
            _ = meter.stops(picture: -0.8, transfer: .ilog, evComp: 0, now: t)
        }
        XCTAssertEqual(meter.offset(for: .ilog), -0.8, accuracy: 0.01)
        // Manual, one stop darker than auto chose: reads -1.0; the offset holds.
        XCTAssertEqual(meter.stops(picture: -1.8, transfer: .ilog, evComp: nil, now: t + 1), -1.0, accuracy: 0.01)
        XCTAssertEqual(meter.offset(for: .ilog), -0.8, accuracy: 0.01)
        // Rec.709 has no seed.
        XCTAssertEqual(meter.stops(picture: 0.4, transfer: .rec709, evComp: nil, now: t + 2), 0.4, accuracy: 1e-9)
    }
}

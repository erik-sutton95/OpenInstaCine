import Insta360Apple
import Insta360Protocol
import OpenCineCameraControls
import OpenCineCore
import OpenInstaViewCore
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

    /// ISO steps exactly as on Insta main, which always sorted the list by value. The shared
    /// stepping sorts only when 160 is listed; Insta's lists are ascending, so both agree.
    func testIsoSteppingMatchesMain() {
        func mainStepped(from current: IsoIndex, stops: Int, available: [IsoIndex]) -> IsoIndex? {
            let list = available.filter { $0 != .auto && ($0 != .iso160 || current == .iso160) }
                .sorted { ($0.isoValue ?? 0) < ($1.isoValue ?? 0) }
            guard current != .auto, let index = list.firstIndex(of: current) else { return nil }
            let next = index + stops
            guard list.indices.contains(next), next != index else { return nil }
            return list[next]
        }
        let lists = [
            LunaShellMapping.isoIndices, ColorMode.iLog.isoIndices, ColorMode.dolbyVision.isoIndices,
            ColorMode.normal.isoIndices, LunaShellMapping.isoIndices.filter { $0 != .iso160 },
        ]
        for available in lists {
            for current in IsoIndex.allCases {
                for stops in [-2, -1, 1, 2] {
                    XCTAssertEqual(
                        IsoIndex.stepped(from: current, stops: stops, available: available),
                        mainStepped(from: current, stops: stops, available: available),
                        "\(current) \(stops) in \(available)")
                }
            }
        }
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
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
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

    func testTimeOfDayTimecodeHasSecondsPrecisionWithoutAFabricatedFrame() {
        // 2026-09-30 08:51:10.54 UTC, Stockholm (UTC+2).
        let t = 1_790_758_270.54
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: t, timeZoneSeconds: 7200), "10:51:10")
        XCTAssertNil(LunaFrameTimecode.timecode(unixSeconds: t, timeZoneSeconds: 7200).frames)
        // Wraps at midnight, west of GMT too.
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: 86_399.99, timeZoneSeconds: 0), "23:59:59")
        XCTAssertEqual(LunaShellMapping.timecode(unixSeconds: 3600, timeZoneSeconds: -7200), "23:00:00")
    }

    func testInsta360FilenameDates() {
        let file = MediaFile(
            path: "/storage_internal/DCIM/Camera01/VID_20260916_123456_00_001.mp4",
            thumbPath: "")
        XCTAssertEqual(file.filenameTimestamp, "20260916123456")
        XCTAssertEqual(MediaHTTP.proxyPaths(file).first?.hasSuffix(".lrv"), true)
    }
}

@MainActor
final class PictureEVMeterTests: XCTestCase {
    private static let ilog = PictureEVContext(
        device: "CAM-1", transfer: .ilog, profile: "i-log", metering: "matrix")

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testLearnsTheAutoExposurePlacementAndReadsManualAgainstIt() {
        let meter = PictureEVMeter(defaults: freshDefaults("PictureEVMeterTests"))
        let ilog = Self.ilog
        // Seeded: auto at EV 0 with the I-Log median 1.3 stops under grey reads 0.
        let first = meter.stops(picture: -1.3, context: ilog, evComp: nil, now: 0)
        XCTAssertEqual(try XCTUnwrap(first.value), 0, accuracy: 1e-9)
        XCTAssertEqual(first.origin, .imageEstimated)
        // Auto at EV 0 in a scene the camera places at -0.8: the offset follows.
        var t = 0.0
        while t < 20 {
            t += 0.04
            _ = meter.stops(picture: -0.8, context: ilog, evComp: 0, now: t)
        }
        XCTAssertEqual(meter.offset(for: ilog), -0.8, accuracy: 0.01)
        // Manual, one stop darker than auto chose: reads -1.0; the offset holds.
        let manual = meter.stops(picture: -1.8, context: ilog, evComp: nil, now: t + 1)
        XCTAssertEqual(try XCTUnwrap(manual.value), -1.0, accuracy: 0.01)
        XCTAssertEqual(meter.offset(for: ilog), -0.8, accuracy: 0.01)
        // Rec.709 has no seed.
        var rec709 = ilog
        rec709.transfer = .rec709
        let plain = meter.stops(picture: 0.4, context: rec709, evComp: nil, now: t + 2)
        XCTAssertEqual(try XCTUnwrap(plain.value), 0.4, accuracy: 1e-9)
    }

    /// Existing installs keep their v1 per-transfer offsets: they seed every new v2 key of the
    /// same transfer, v1 is never written or removed, and running it again changes nothing.
    func testV1OffsetsSeedNewKeysIdempotentlyAndSurvive() {
        let defaults = freshDefaults("PictureEVMeterMigrationTests")
        let legacy: [String: Double] = [MonitorTransfer.ilog.rawValue: -0.6]
        defaults.set(legacy, forKey: PictureEVMeter.legacyDefaultsKey)
        var otherCamera = Self.ilog
        otherCamera.device = "CAM-2"
        var faceMetering = Self.ilog
        faceMetering.metering = "face"

        for run in 0..<2 {
            let meter = PictureEVMeter(defaults: defaults)
            XCTAssertEqual(meter.offset(for: otherCamera), -0.6, accuracy: 1e-9, "run \(run)")
            XCTAssertEqual(meter.offset(for: faceMetering), -0.6, accuracy: 1e-9, "run \(run)")
            meter.save()
            XCTAssertEqual(
                defaults.dictionary(forKey: PictureEVMeter.legacyDefaultsKey) as? [String: Double], legacy)
        }

        // Learning one context writes only its v2 key; the others still read v1.
        let learner = PictureEVMeter(defaults: defaults)
        var t = 0.0
        while t < 20 {
            t += 0.04
            _ = learner.stops(picture: -1.0, context: Self.ilog, evComp: 0, now: t)
        }
        learner.save()
        let stored = defaults.dictionary(forKey: PictureEVMeter.defaultsKey) as? [String: Double] ?? [:]
        XCTAssertEqual(Set(stored.keys), [Self.ilog.key])
        let reread = PictureEVMeter(defaults: defaults)
        XCTAssertEqual(reread.offset(for: Self.ilog), -1.0, accuracy: 0.01)
        XCTAssertEqual(reread.offset(for: otherCamera), -0.6, accuracy: 1e-9)
        XCTAssertEqual(defaults.dictionary(forKey: PictureEVMeter.legacyDefaultsKey) as? [String: Double], legacy)
    }

    /// A source saves only its own keys, so a second source's learning is never overwritten.
    func testTwoSourcesSharingStorageKeepTheirOwnOffsets() {
        let defaults = freshDefaults("PictureEVMeterSourcesTests")
        var second = Self.ilog
        second.device = "CAM-2"
        let a = PictureEVMeter(defaults: defaults)
        let b = PictureEVMeter(defaults: defaults)
        var t = 0.0
        while t < 20 {
            t += 0.04
            _ = a.stops(picture: -0.4, context: Self.ilog, evComp: 0, now: t)
            _ = b.stops(picture: -2.2, context: second, evComp: 0, now: t)
        }
        a.save()
        b.save()
        a.save()
        let reread = PictureEVMeter(defaults: defaults)
        XCTAssertEqual(reread.offset(for: Self.ilog), -0.4, accuracy: 0.01)
        XCTAssertEqual(reread.offset(for: second), -2.2, accuracy: 0.01)
    }
}

@MainActor
final class LunaDoubleTapTrackTests: XCTestCase {
    func testSecondTapNearbyAndQuickIsADoubleTap() {
        XCTAssertTrue(CameraSession.isDoubleTap(from: (10, 0.5, 0.5), to: (10.3, 0.53, 0.52)))
        XCTAssertFalse(CameraSession.isDoubleTap(from: (10, 0.5, 0.5), to: (10.5, 0.5, 0.5)), "too slow")
        XCTAssertFalse(CameraSession.isDoubleTap(from: (10, 0.5, 0.5), to: (10.2, 0.6, 0.5)), "too far")
    }

    func testTrackBoxIsCentredAndStaysInFrame() {
        let centre = CameraSession.doubleTapTrackBox(x: 0.5, y: 0.5)
        XCTAssertEqual(centre.x + centre.width / 2, 0.5, accuracy: 1e-9)
        XCTAssertEqual(centre.y + centre.height / 2, 0.5, accuracy: 1e-9)
        XCTAssertEqual(centre.height, centre.width * 16 / 9, accuracy: 1e-9)
        XCTAssertFalse(centre.isTooSmall)
        let corner = CameraSession.doubleTapTrackBox(x: 0.99, y: 0.01)
        XCTAssertEqual(corner.maxX, 1, accuracy: 1e-9)
        XCTAssertEqual(corner.minY, 0, accuracy: 1e-9)
    }
}

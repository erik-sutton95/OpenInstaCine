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
}

import CoreImage
import Metal
import OpenCineApple
import OpenCineCameraControls
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

@MainActor
final class LUTAssistTests: XCTestCase {
    private let keys = [
        "OpenInstaCine.Assist.v1",
        "OpenInstaCine.PlaybackAssists.v1",
        "OpenInstaCine.LUTSelection",
        "OpenInstaCine.CustomRec709File",
        "OpenInstaCine.CustomDLogFile",
        "OpenInstaCine.CustomDLog2File",
        "OpenInstaCine.SelectedCustomLUTFile",
        "OpenInstaCine.LastLUT",
        "OpenInstaCine.LastCustomLUT",
        "OpenInstaCine.LastLUTWasCustom",
        "OpenInstaCine.LastMonitorColorMode",
        "OpenInstaCine.CacheFullResolution",
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        saved.removeAll()
        super.tearDown()
    }

    func testAutoLUTFollowsPersistedLiveColorWhenOffline() {
        let live = LiveAssistState()
        live.syncLUT(to: .iLog)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .iLog)

        let offline = LiveAssistState()
        XCTAssertEqual(offline.monitorColorMode, .iLog)
        XCTAssertEqual(offline.resolvedSource(), .iLogRec709)
        offline.togglePlayback(.lut)
        XCTAssertGreaterThanOrEqual(offline.playbackEffects.lutDimension, 2)
        XCTAssertTrue(offline.playbackEffects.needsGPUFeed)
    }

    func testPlaybackAutoDoesNotDropLogWhenLiveReportsRec709() {
        XCTAssertEqual(PlaybackLUTColor.resolve(live: .normal, last: .iLog), .iLog)
        let color = PlaybackLUTColor.resolve(live: .normal, last: .iLog)
        let assist = LiveAssistState()
        assist.syncLUT(to: color)
        assist.togglePlayback(.lut)
        XCTAssertEqual(assist.resolvedSource(), .iLogRec709)
        XCTAssertGreaterThanOrEqual(assist.playbackEffects.lutDimension, 2)
    }

    func testClipColorGammaWinsAndDoesNotPersistOverLastLive() {
        XCTAssertEqual(
            PlaybackLUTColor.resolve(clip: .dLog2, live: .normal, last: .dLog), .dLog2)
        XCTAssertEqual(
            PlaybackLUTColor.resolve(clip: .normal, live: .dLog2, last: .dLog2), .normal)
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)
        assist.adoptPlaybackColor(.normal)
        XCTAssertEqual(assist.monitorColorMode, .normal)
        XCTAssertEqual(
            LUTPreferences.app.lastMonitorColorMode, .dLog2,
            "a Rec.709 clip must not overwrite last live log")
        assist.adoptPlaybackColor(.dLog2)
        assist.togglePlayback(.lut)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testLUTPickerAppearDoesNotReplaceClipAutoWithLiveSet() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)
        assist.adoptPlaybackColor(.dLog)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        assist.bindLUTPicker(live: .dLog2, inPlayback: true)
        XCTAssertEqual(assist.monitorColorMode, .dLog)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        XCTAssertEqual(
            LUTPreferences.app.lastMonitorColorMode, .dLog2,
            "opening LUT in playback must not persist the live SET over the clip")
        assist.bindLUTPicker(live: .dLog2, inPlayback: false)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testDisconnectedMediaLUTPickerKeepsClipAuto() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .normal)
        assist.adoptPlaybackColor(.dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        assist.gradesClip = true
        assist.bindLUTPicker(live: nil, inPlayback: false)
        XCTAssertEqual(assist.monitorColorMode, .dLog2)
        XCTAssertEqual(
            assist.resolvedSource(), .dji(.pocketDLog2),
            "disconnected library has no camera inPlayback; clip color must still drive Auto")
        assist.gradesClip = false
        assist.bindLUTPicker(live: .normal, inPlayback: false)
        XCTAssertEqual(assist.resolvedSource(), .off)
    }

    func testCreativeLooksBindGeneratedCubes() {
        let assist = LiveAssistState()
        assist.selectLUT(.creativeMono)
        XCTAssertEqual(assist.resolvedSource(), .creative(.mono))
        XCTAssertEqual(assist.lutStatusLabel, "Mono")
        XCTAssertGreaterThanOrEqual(assist.effects.lutDimension, 2)
        XCTAssertFalse(assist.effects.lutRGBA.isEmpty)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .creativeMono)
    }

    func testFreshInstallDefaultsToAuto() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.lutSelection, .officialAuto)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(assist.lutExposureStops, 0)
        XCTAssertFalse(LUTAssist.exposureHelp.isEmpty)
        XCTAssertEqual(
            CustomLUTSlot.allCases.map(\.title),
            ["Custom", "Custom D-Log", "Custom D-Log2"])
    }

    func testLUTExposureNudgeSnapsAndRebuildsTheCube() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .iLog)
        guard BundledLunaLUT.iLogToRec709 != nil else {
            XCTFail("official Luna I-Log cube must load from the app bundle")
            return
        }
        let nominal = assist.effects.lutRGBA
        XCTAssertFalse(nominal.isEmpty)
        assist.nudgeLUTExposure(-1)
        XCTAssertEqual(assist.lutExposureStops, -1)
        XCTAssertNotEqual(assist.effects.lutRGBA, nominal, "pull must remap cube inputs")
        assist.nudgeLUTExposure(-0.5)
        XCTAssertEqual(assist.lutExposureStops, -1.5)
        assist.nudgeLUTExposure(0.5)
        XCTAssertEqual(assist.lutExposureStops, -1)
        for _ in 0..<6 { assist.nudgeLUTExposure(-0.5) }
        XCTAssertEqual(assist.lutExposureStops, -3)
        assist.nudgeLUTExposure(-0.5)
        XCTAssertEqual(assist.lutExposureStops, -3)
    }

    func testExportCubeBakesExposureOnlyWhenAsked() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .iLog)
        guard BundledLunaLUT.iLogToRec709 != nil else {
            XCTFail("official Luna I-Log cube must load from the app bundle")
            return
        }
        assist.nudgeLUTExposure(-1)
        let nominal = assist.exportLUTCube(bakeExposure: false)
        let pulled = assist.exportLUTCube(bakeExposure: true)
        XCTAssertNotNil(nominal)
        XCTAssertNotNil(pulled)
        XCTAssertNotEqual(
            nominal, pulled, "Bake exposure must remap cube inputs the same way as the monitor")
        XCTAssertEqual(assist.exportLUTCube(bakeExposure: true), pulled)
        assist.nudgeLUTExposure(1)
        XCTAssertEqual(
            assist.exportLUTCube(bakeExposure: true),
            assist.exportLUTCube(bakeExposure: false),
            "0.0 stops is the cube as shipped")
    }

    func testLUTExposurePersistsAcrossAssistReload() {
        let assist = LiveAssistState()
        assist.nudgeLUTExposure(-2)
        XCTAssertEqual(assist.lutExposureStops, -2)
        let restored = LiveAssistState()
        XCTAssertEqual(restored.lutExposureStops, -2)
    }

    func testManualCustomRec709SticksUntilAuto() throws {
        let cube = try writeTempCube(named: "opc-test-manual-rec709.cube")
        defer { try? CustomLUTStore.app.clear(.rec709) }
        _ = try CustomLUTStore.app.importFile(from: cube, into: .rec709)

        let assist = LiveAssistState()
        assist.selectLUT(.customRec709)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .customRec709)
        XCTAssertEqual(assist.resolvedSource(), .custom(.rec709))

        assist.selectLUT(.officialAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testChipToggleKeepsSelection() {
        let assist = LiveAssistState()
        assist.selectLUT(.djiDLog2)
        assist.toggle(.lut)
        XCTAssertFalse(assist.lutEnabled)
        XCTAssertEqual(assist.lutSelection, .djiDLog2)
        XCTAssertEqual(assist.lutStatusLabel, "Off · D-Log2 → Rec.709")
        XCTAssertEqual(assist.effects.lutDimension, 0)
        XCTAssertFalse(
            assist.effects.needsGPUFeed, "LUT off with no other GPU assist uses the HEVC layer")
        assist.toggle(.lut)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(assist.lutSelection, .djiDLog2)
    }

    func testCustomSlotsAreIndependentAndAutoUsesThem() throws {
        let rec709 = try writeTempCube(named: "opc-test-rec709.cube")
        let dlog = try writeTempCube(named: "opc-test-dlog.cube")
        let dlog2 = try writeTempCube(named: "opc-test-dlog2.cube")
        defer {
            try? CustomLUTStore.app.clear(.rec709)
            try? CustomLUTStore.app.clear(.dLog)
            try? CustomLUTStore.app.clear(.dLog2)
        }
        _ = try CustomLUTStore.app.importFile(from: rec709, into: .rec709)
        _ = try CustomLUTStore.app.importFile(from: dlog, into: .dLog)
        _ = try CustomLUTStore.app.importFile(from: dlog2, into: .dLog2)
        XCTAssertTrue(CustomLUTStore.app.hasCube(.rec709))
        XCTAssertTrue(CustomLUTStore.app.hasCube(.dLog))
        XCTAssertTrue(CustomLUTStore.app.hasCube(.dLog2))
        XCTAssertEqual(LUTPreferences.app.customFileName(for: .rec709), "opc-test-rec709.cube")

        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog)
        XCTAssertEqual(assist.lutSelection, .officialAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        assist.selectLUT(.customFile)
        LUTPreferences.app.selectedCustomFileName = "opc-test-dlog.cube"
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .file("opc-test-dlog.cube"))
        assist.selectLUT(.officialAuto)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        assist.syncLUT(to: .normal)
        XCTAssertEqual(assist.resolvedSource(), .off)
    }

    func testOfficialCubesParseAsSize33() throws {
        XCTAssertNotNil(
            Bundle.main.url(forResource: BundledLunaLUT.resourceName, withExtension: "cube"),
            "the Luna I-Log cube must ship in the app bundle")
        let cube = try lunaCube()
        XCTAssertEqual(cube.size, 33)
        XCTAssertEqual(cube.rgb.count, 33 * 33 * 33 * 3)
        XCTAssertNotNil(BundledLunaLUT.iLogToRec709)
        for lut in OfficialDJILUT.allCases {
            XCTAssertNil(
                Bundle.main.url(forResource: lut.resourceName, withExtension: "cube"),
                "\(lut.fileName) must not ship in the Luna app")
        }
    }

    func testArmedExplicitAutoILogBindsOfficialCube() {
        let assist = LiveAssistState()
        assist.selectLUT(.officialAuto)
        assist.syncLUT(to: .iLog, family: .pocket, cameraName: "Luna Ultra")
        XCTAssertEqual(assist.lutSelection, .officialAuto)
        XCTAssertEqual(assist.resolvedSource(), .iLogRec709)
        XCTAssertEqual(assist.lutStatusLabel, "Auto · I-Log → Rec.709")
        guard BundledLunaLUT.iLogToRec709 != nil else {
            XCTFail("official Luna I-Log cube must load from the app bundle")
            return
        }
        XCTAssertEqual(assist.effects.lutDimension, 33)
        XCTAssertFalse(assist.effects.lutRGBA.isEmpty)
        XCTAssertTrue(assist.effects.needsGPUFeed)
    }

    func testOfficialILogCubeMovesMidGrey() throws {
        let cube = try lunaCube()
        let g = Float(MonitorTransfer.ilog.middleGrayEncoded)
        let out = cube.map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(abs(out.red - g), 0.01, "18% I-Log must not be identity")
        XCTAssertGreaterThan(abs(out.green - g), 0.01)
        XCTAssertGreaterThan(abs(out.blue - g), 0.01)
        let b = Float(MonitorTransfer.ilog.encodeLinear(0))
        let black = cube.map(red: b, green: b, blue: b)
        XCTAssertLessThan(black.red, 0.04, "log black must become a real Rec.709 black")
    }

    func testArmedAutoILogBindsOfficialCube() {
        let assist = LiveAssistState()
        XCTAssertTrue(assist.lutEnabled)
        assist.syncLUT(to: .iLog)
        XCTAssertEqual(assist.lutSelection, .officialAuto)
        XCTAssertEqual(assist.resolvedSource(), .iLogRec709)
        XCTAssertEqual(assist.lutStatusLabel, "Auto · I-Log → Rec.709")
        guard BundledLunaLUT.iLogToRec709 != nil else {
            XCTFail("official Luna I-Log cube must load from the app bundle")
            return
        }
        XCTAssertEqual(assist.effects.lutDimension, 33)
        XCTAssertFalse(assist.effects.lutRGBA.isEmpty)
        XCTAssertTrue(assist.effects.needsGPUFeed)
    }

    func testPhotoLiveViewBypassesStaleLogAndRestoresVideo() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)
        XCTAssertEqual(assist.lutSelection, .officialAuto)
        XCTAssertTrue(assist.lutEnabled)

        assist.syncLUT(to: .dLog2, isPhoto: true)
        XCTAssertEqual(assist.monitorColorMode, .normal)
        XCTAssertEqual(assist.effects.colorMode, .normal)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(assist.lutStatusLabel, "Auto · Rec.709")
        XCTAssertEqual(assist.lutSelection, .officialAuto)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)
        XCTAssertEqual(assist.effects.lutDimension, 0)

        assist.syncLUT(to: .dLog2, isPhoto: false)
        XCTAssertEqual(assist.monitorColorMode, .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertEqual(assist.lutStatusLabel, "Auto · D-Log2 → Rec.709")
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)
    }

    func testLivePhotoMatchesPhotoRec709() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLogM, isPhoto: true)
        XCTAssertEqual(assist.monitorColorMode, .normal)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(
            LiveMonitorColorScience.colorMode(isPhoto: true, colorMode: .dLog2), .normal)
        XCTAssertEqual(
            LiveMonitorColorScience.transfer(isPhoto: true, colorMode: .dLog2), .rec709)
        var status = CameraStatus()
        status.colorMode = .dLog2
        status.shootingMode = Int(ShootingMode.livePhoto.rawValue)
        XCTAssertTrue(status.isPhoto)
        XCTAssertEqual(
            LiveMonitorColorScience.colorMode(isPhoto: status.isPhoto, colorMode: status.colorMode),
            .normal)
        status.shootingMode = Int(ShootingMode.photoRawPocket3AndNano)
        XCTAssertTrue(status.isPhoto)
        status.shootingMode = Int(ShootingMode.video.rawValue)
        XCTAssertFalse(status.isPhoto)
        XCTAssertEqual(
            LiveMonitorColorScience.colorMode(isPhoto: status.isPhoto, colorMode: status.colorMode),
            .dLog2)
    }

    func testPhotoKeepsCreativeAndGenericCustom() throws {
        let assist = LiveAssistState()
        assist.selectLUT(.creativeWarm)
        assist.syncLUT(to: .dLog2, isPhoto: true)
        XCTAssertEqual(assist.lutSelection, .creativeWarm)
        XCTAssertEqual(assist.resolvedSource(), .creative(.warm))
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, nil)

        let cube = try writeTempCube(named: "opc-test-photo-rec709.cube")
        defer { try? CustomLUTStore.app.clear(.rec709) }
        _ = try CustomLUTStore.app.importFile(from: cube, into: .rec709)
        assist.selectLUT(.customRec709)
        assist.syncLUT(to: .dLog2, isPhoto: true)
        XCTAssertEqual(assist.lutSelection, .customRec709)
        XCTAssertEqual(assist.resolvedSource(), .custom(.rec709))
        assist.selectCustomFile("opc-test-photo-rec709.cube")
        XCTAssertEqual(assist.resolvedSource(), .file("opc-test-photo-rec709.cube"))
        XCTAssertGreaterThan(assist.effects.lutDimension, 1)
    }

    func testPhotoBypassesManualTechnicalAndCustomLogSlots() throws {
        let assist = LiveAssistState()
        assist.selectLUT(.djiDLog2)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        assist.syncLUT(to: .dLog2, isPhoto: true)
        XCTAssertEqual(assist.lutSelection, .djiDLog2)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)

        let dlog = try writeTempCube(named: "opc-test-photo-dlog.cube")
        defer { try? CustomLUTStore.app.clear(.dLog) }
        _ = try CustomLUTStore.app.importFile(from: dlog, into: .dLog)
        assist.selectLUT(.customDLog)
        assist.syncLUT(to: .dLog, isPhoto: true)
        XCTAssertEqual(assist.lutSelection, .customDLog)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(OfficialLUTs.app.catalog(true), [.officialAuto])
        XCTAssertEqual(OfficialLUTs.app.catalog(false), [.officialAuto, .iLogRec709])
        XCTAssertEqual(LUTPickerCopy.photoRec709Caption, "Photo live view is Rec.709 — log conversions are off")
    }

    func testPlaybackClipColorWinsWhileCameraStaysPhoto() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        assist.syncLUT(to: .dLog2, isPhoto: true)
        XCTAssertEqual(assist.resolvedSource(), .off)
        assist.gradesClip = true
        assist.adoptPlaybackColor(.dLog2)
        XCTAssertFalse(assist.liveIsPhoto)
        XCTAssertEqual(assist.monitorColorMode, .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .dLog2)
        assist.bindLUTPicker(live: .normal, inPlayback: true, isPhoto: true)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        assist.gradesClip = false
        assist.syncLUT(to: .dLog2, isPhoto: true)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(assist.lutSelection, .officialAuto)
    }

    /// Values Insta main wrote still load: the LUT raw value and the color mode byte did not change
    /// when the cases moved to OpenCine's vocabulary under capability names.
    func testValuesStoredByMainStillLoad() {
        UserDefaults.standard.set("lunaILog", forKey: "OpenInstaCine.LUTSelection")
        UserDefaults.standard.set(0xE2, forKey: "OpenInstaCine.LastMonitorColorMode")
        XCTAssertEqual(LUTPreferences.app.lutSelection, .iLogRec709)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .iLog)
        LUTPreferences.app.lutSelection = .iLogRec709
        XCTAssertEqual(UserDefaults.standard.string(forKey: "OpenInstaCine.LUTSelection"), "lunaILog")
    }

    func testPhotoDoesNotMutateSavedLUTPrefs() {
        let assist = LiveAssistState()
        assist.selectLUT(.iLogRec709)
        assist.syncLUT(to: .iLog)
        XCTAssertTrue(assist.lutEnabled)
        assist.syncLUT(to: .iLog, isPhoto: true)
        XCTAssertEqual(assist.lutSelection, .iLogRec709)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(LUTPreferences.app.lutSelection, .iLogRec709)
        let restored = LiveAssistState()
        XCTAssertEqual(restored.lutSelection, .iLogRec709)
        XCTAssertTrue(restored.lutEnabled)
        XCTAssertEqual(LUTPreferences.app.lastMonitorColorMode, .iLog)
    }

    func testOfficialILogBakeKeepsRec709Codes() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = try lunaCube()
        let g = Float(MonitorTransfer.ilog.middleGrayEncoded)
        let expected = cube.map(red: g, green: g, blue: g)
        let code = UInt8(clamping: Int((Double(g) * 255).rounded()))
        let source = Self.solidImage(code: code)
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let graded = LiveMonitorCompositor.apply(to: source, effects: fx)

        let baker = MonitorFrameBaker(device: device)
        let drawable = CGSize(width: 32, height: 32)
        let done = expectation(description: "bake")
        baker.scheduleBake(
            image: graded, drawableSize: drawable, pixelFormat: .bgra8Unorm
        ) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
            XCTFail("baker must publish the LUT texture")
            return
        }
        defer { baker.releaseBakedTexture(texture) }
        guard
            let wrapped = CIImage(
                mtlTexture: texture, options: MonitorWorkingSpace.imageOptions)
        else {
            XCTFail("CIImage(mtlTexture:) must wrap the bake")
            return
        }
        let sample = Self.sampleRGB(wrapped)
        XCTAssertEqual(sample.0, expected.red, accuracy: 0.06)
        XCTAssertEqual(sample.1, expected.green, accuracy: 0.06)
        XCTAssertEqual(sample.2, expected.blue, accuracy: 0.06)
        XCTAssertGreaterThan(
            abs(sample.0 - 0.64), 0.12,
            "DeviceRGB re-encode of the cube output looks like uncorrected log")
    }

    private func writeTempCube(named fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let text = """
            LUT_3D_SIZE 2
            0 0 0
            1 0 0
            0 1 0
            1 1 0
            0 0 1
            1 0 1
            0 1 1
            1 1 1
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func lunaCube() throws -> CubeLUT {
        try CubeLUT.parse(
            String(
                contentsOf: officialCubeURL(BundledLunaLUT.resourceName + ".cube"),
                encoding: .utf8))
    }

    private func officialCubeURL(_ fileName: String) -> URL {
        let resource = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if let bundled = Bundle.main.url(forResource: resource, withExtension: "cube") {
            return bundled
        }
        if let nested = Bundle.main.url(
            forResource: resource, withExtension: "cube", subdirectory: "Resources")
        {
            return nested
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OpenInstaCine/Resources/\(fileName)")
    }

    private static func solidImage(code: UInt8, width: Int = 16, height: Int = 16) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = code
            bytes[i * 4 + 1] = code
            bytes[i * 4 + 2] = code
            bytes[i * 4 + 3] = 255
        }
        return CIImage(
            bitmapData: Data(bytes), bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8, colorSpace: nil)
    }

    private static func sampleRGB(_ image: CIImage) -> (Float, Float, Float) {
        let context = CIContext(options: MonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) / 255, Float(bytes[1]) / 255, Float(bytes[2]) / 255)
    }
}

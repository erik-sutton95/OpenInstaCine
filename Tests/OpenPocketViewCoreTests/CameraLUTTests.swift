import Foundation
import OpenPocketViewCore
import Testing

@Suite struct CameraLUTTests {
    private let look = CameraLUT(
        id: "insta360-luna-ilog-rec709-v2", title: "I-Log → Rec.709",
        fileName: "Luna_I-Log_to_Rec709_BT1886_s33_v2.cube", inputTransfer: .ilog)

    @Test func catalogChoiceKeepsStableStringPersistence() throws {
        let selection = LUTSelection.camera(look.id)
        #expect(selection.rawValue == "camera:insta360-luna-ilog-rec709-v2")
        #expect(LUTSelection(rawValue: selection.rawValue) == selection)
        #expect(selection.title(cameraLUTs: [look]) == look.title)
        #expect(try JSONDecoder().decode(LUTSelection.self, from: JSONEncoder().encode(selection)) == selection)
        for old in LUTSelection.allCases {
            #expect(LUTSelection(rawValue: old.rawValue) == old)
            #expect(try JSONDecoder().decode(LUTSelection.self, from: JSONEncoder().encode(old)) == old)
        }
        #expect(LUTSelection(rawValue: "camera:") == nil)
    }

    @Test func onlyAuthoritativePreviewCanSelectAutomaticCameraConversion() {
        #expect(resolve(.auto, preview: .rec709) == .off)
        #expect(resolve(.auto, preview: nil) == .off)
        #expect(resolve(.auto, preview: .ilog) == .camera(look))
        #expect(resolve(.camera(look.id), preview: .rec709) == .camera(look))
        #expect(resolve(.camera("unknown"), preview: .ilog) == .off)
        #expect(LUTResolver.resolve(
            selection: .auto, colorMode: .dLog2, hasCustomDLog: false, hasCustomDLog2: false,
            cameraLUTs: [look], previewTransfer: .rec709) == .off,
            "A recording profile cannot double-convert an already rendered preview")
        #expect(LUTResolver.statusLabel(enabled: false, selection: .camera(look.id), source: .camera(look))
            == "Off · I-Log → Rec.709")
        #expect(LUTResolver.resolve(
            selection: .auto, colorMode: .normal, hasCustomDLog: false, hasCustomDLog2: false,
            previewTransfer: .dlog2) == .dji(.pocketDLog2),
            "An authoritative legacy log source keeps its automatic camera conversion")
    }

    @Test func officialCubeMatchesIndependentWhitePaperSamples() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/CameraLUTs/luts/\(look.fileName)")
        let cube = try CubeLUT.parse(String(contentsOf: url, encoding: .utf8))
        #expect(cube.size == 33)
        #expect(cube.rgb.count == 35_937 * 3)
        let samples: [(Double, Float, Float, Float)] = [
            (0, 0.00438712, 0.00437246, 0.00425046),
            (0.18, 0.38463754, 0.38836461, 0.38811411),
            (1, 0.75309980, 0.75316732, 0.75308445),
            (22, 0.99942007, 0.99942008, 0.99942008),
        ]
        for (scene, r, g, b) in samples {
            let code = Float(LiveColorScience.encode(scene, transfer: .ilog))
            let pixel = cube.map(red: code, green: code, blue: code)
            #expect(abs(pixel.red - r) < 0.000002)
            #expect(abs(pixel.green - g) < 0.000002)
            #expect(abs(pixel.blue - b) < 0.000002)
        }
    }

    private func resolve(_ selection: LUTSelection, preview: MonitorTransfer?) -> LUTSource {
        LUTResolver.resolve(selection: selection, colorMode: nil,
            hasCustomDLog: false, hasCustomDLog2: false,
            cameraLUTs: [look], previewTransfer: preview)
    }
}

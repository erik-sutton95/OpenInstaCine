import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct LUTLibraryWireTests {
    @Test func officialILogCubeUsesNeutralBridgeForExposure() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: root.appendingPathComponent(
            "Resources/CameraLUTs/luts/Luna_I-Log_to_Rec709_BT1886_s33_v2.cube"))
        // Independently sampled official cube at I-Log decode(13/32) × 2^EV,
        // then quantized to the GLES atlas's RGBA8 format.
        let fixtures: [(Double, [UInt8])] = [
            (-1, [58, 59, 59, 255]), (0, [93, 93, 93, 255]), (1, [129, 130, 130, 255]),
        ]
        let offset = (13 * 33 * 33 + 13 * 33 + 13) * 4
        for (ev, expected) in fixtures {
            let packed = try #require(LUTLibraryWire.packedImportedLUT(
                utf8: Array(bytes), exposureStops: ev, colorModeCode: FeedEffectsWire.iLogTransferCode))
            #expect(packed.count == 33 * 33 * 33 * 4)
            #expect(Array(packed[offset..<(offset + 4)]) == expected)
        }
    }

    @Test
    func rejectsPathEscapeAndBadNames() {
        #expect(LUTLibraryWire.isSafeStoredFileName("Look.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("../Look.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("dir/Look.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("Look:cube.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("Look.CUBE.bak"))
    }

    @Test
    func identity2CubePacks32Bytes() throws {
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
        let utf8 = Array(text.utf8)
        let record = try #require(LUTLibraryWire.validatedImport(utf8: utf8, fileName: "Look.cube"))
        #expect(record.hasPrefix("1\u{001F}2\u{001F}"))
        let packed = try #require(LUTLibraryWire.packedImportedLUT(utf8: utf8))
        #expect(packed.count == 2 * 2 * 2 * 4)
        // (r=1,g=0,b=1) → dst (g*n² + b*n + r)*4 = (0 + 2 + 1)*4 = 12
        #expect(packed[12] == 255)
        #expect(packed[13] == 0)
        #expect(packed[14] == 255)
        #expect(packed[15] == 255)
    }

    @Test
    func exposurePullRemapsPackedIdentity() throws {
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
        let utf8 = Array(text.utf8)
        let identity = try #require(LUTLibraryWire.packedImportedLUT(utf8: utf8))
        let pulled = try #require(
            LUTLibraryWire.packedImportedLUT(
                utf8: utf8, exposureStops: -1, colorModeCode: Int(ColorMode.dLog2.rawValue)))
        #expect(pulled.count == identity.count)
        #expect(pulled != identity)
    }

    @Test
    func creativeMonoPacksAGreyscaleCube() throws {
        let packed = try #require(LUTLibraryWire.packedCreativeLook("Mono"))
        #expect(!packed.isEmpty)
        #expect(packed.count % 4 == 0)
    }
}

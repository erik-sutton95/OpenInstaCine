import Testing

@testable import OpenPocketViewCore

/// Bytes from the Action 6 survey (2026-09-21, V01.02.0521); handbook `devices/action-6/`.
@Suite struct Action6Tests {
    let action6 = CameraModel.resolve(modelId: 0x18, name: nil)

    @Test func colorIsNormal10AndDLogMOnNanoBytes() {
        #expect(ColorMode.available(for: action6) == [.normal10, .dLogM])
        #expect(ColorMode.normal10.wireByte(for: action6) == 0x3F)
        #expect(ColorMode.dLogM.wireByte(for: action6) == 0x3D)
        #expect(ColorMode.fromWire(0x3F, model: action6) == .normal10)
        #expect(ColorMode.fromWire(0x3D, model: action6) == .dLogM)
        #expect(CamCapColorMode.parse([0x01, 0x03, 0x00, 0x02, 0x3F, 0x3D], model: action6) == [
            .normal10, .dLogM,
        ])
        #expect(OfficialDJILUT.auto(colorMode: .dLogM, family: .other, cameraName: action6.name)
            == .action6DLogM)
    }

    @Test func apertureFallbackFollowsExposureAndMode() {
        #expect(ApertureStrategy.fallback(expoMode: .auto, shootingMode: 1) == [
            .auto, .f28, .starburst,
        ])
        #expect(ApertureStrategy.fallback(expoMode: .manual, shootingMode: 1) == [
            .f26, .f28, .starburst,
        ])
        #expect(ApertureStrategy.fallback(expoMode: .auto, shootingMode: 0x28) == [
            .f2, .f28, .starburst,
        ])
    }

}

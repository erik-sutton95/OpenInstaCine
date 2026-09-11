import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct FeedEffectsWireTests {
    @Test
    func neutralILogIdentifierIsResolvedBeforeLegacyCameraBytes() {
        #expect(FeedEffectsWire.iLogTransferCode == 65_536)
        #expect(FeedEffectsWire.monitorTransfer(colorModeCode: 65_536) == .ilog)
        #expect(FeedEffectsWire.monitorTransfer(colorModeCode: Int(ColorMode.dLog.rawValue)) == .dlog)
        #expect(FeedEffectsWire.monitorTransfer(colorModeCode: Int(ColorMode.dLog2.rawValue)) == .dlog2)
        #expect(FeedEffectsWire.monitorTransfer(colorModeCode: Int(ColorMode.hdr.rawValue)) == .hdr)
        for unknown in [-1, 256, 65_535, 65_537, Int.max] {
            #expect(FeedEffectsWire.monitorTransfer(colorModeCode: unknown) == .rec709)
        }
    }

    @Test
    func iLogAssistScalarsUsePaperCeilingGrayAndLogPeaking() {
        for iso in [100, 1600, 6400] {
            let grayIRE = MonitorTransfer.ilog.middleGrayPaperIRE
            let scalars = FeedEffectsWire.assistScalars(
                colorModeCode: FeedEffectsWire.iLogTransferCode,
                iso: iso, highlightIRE: 100, midtoneIRE: grayIRE)
            #expect(scalars.count == FeedEffectsWire.assistScalarCount)
            #expect(scalars[0] == 1)
            #expect(scalars[3] == 1)
            // The asymmetric anchored axis can shift the stripe centre slightly;
            // its low/high endpoints must still straddle published middle gray.
            let gray = Float(MonitorTransfer.ilog.middleGrayEncoded)
            #expect(scalars[1] - scalars[2] < gray)
            #expect(scalars[1] + scalars[2] > gray)
        }
    }

    @Test
    func iLogStopsPaintNeutralAndSaturatedGrayExposureInTheSameBand() throws {
        let packed = try #require(FeedEffectsWire.packedFalseColorPaint(
            scaleOrdinal: 0, colorModeCode: FeedEffectsWire.iLogTransferCode, iso: 100))
        let size = FeedEffectsWire.falseColorCubeSize
        #expect(size == 64)
        // Independently sampled 64-grid fixtures using the paper inverse and
        // BT.2020 weights. Each is safely inside the 18% band's +/- 1/6 stop,
        // despite very different encoded luma. The 6/63 channels sit near black.
        let fixtures: [(r: Int, g: Int, b: Int, linearY: Double)] = [
            (27, 27, 27, 0.1905425137189525),
            (37, 6, 6, 0.19225917425245362),
            (6, 29, 6, 0.17000017415402868),
            (6, 6, 48, 0.18445943714624385),
        ]
        for fixture in fixtures {
            #expect(abs(log2(fixture.linearY / 0.18)) < 0.11)
            // GLES atlas packs x = b * size + r, y = g.
            let offset = ((fixture.g * size + fixture.b) * size + fixture.r) * 4
            let red = Int(packed[offset])
            let green = Int(packed[offset + 1])
            let blue = Int(packed[offset + 2])
            // 18% palette (8,203,24), at 60% paint + 40% neutral detail.
            // Removing the equal-channel detail leaves the same green contrast;
            // allow one code of independently rounded RGBA8 quantization.
            #expect(abs((green - red) - 117) <= 1)
            #expect(abs((green - blue) - 107) <= 1)
            #expect(packed[offset + 3] == 255)
        }
    }

    @Test
    func iLogIrePaintKeepsTheEncodedLumaAxis() throws {
        let packed = try #require(FeedEffectsWire.packedFalseColorPaint(
            scaleOrdinal: 1, colorModeCode: FeedEffectsWire.iLogTransferCode, iso: 100))
        let size = FeedEffectsWire.falseColorCubeSize
        let offset = ((6 * size + 6) * size + 37) * 4
        // The red-dominant Stops fixture falls between the colored IRE bands on
        // the encoded axis, so IRE retains neutral detail instead of green paint.
        #expect(packed[offset] == packed[offset + 1])
        #expect(packed[offset + 1] == packed[offset + 2])
        #expect(packed[offset] > 0)
        #expect(packed[offset + 3] == 255)
    }

    @Test
    func assistScalarsMapDLog2HighlightToLiveTapCeiling() {
        ScopeExposureCeiling.reset()
        let scalars = FeedEffectsWire.assistScalars(
            colorModeCode: Int(ColorMode.dLog2.rawValue),
            iso: 1600,
            highlightIRE: 100,
            midtoneIRE: LiveZebra.midtoneIRE)
        #expect(scalars.count == FeedEffectsWire.assistScalarCount)
        let clip = Float(ScopeExposureCeiling.dlog2LiveTapByteAt1600) / 255
        #expect(abs(scalars[0] - clip) < 0.01)
        #expect(scalars[3] == 1)
    }

    @Test
    func rec709PeakingGateIsSquaredDisplayGradient() {
        let scalars = FeedEffectsWire.assistScalars(
            colorModeCode: Int(ColorMode.normal.rawValue),
            iso: 100,
            highlightIRE: 100,
            midtoneIRE: 55)
        #expect(abs(Double(scalars[3]) - 1.57 * 1.57) < 1e-5)
        #expect(abs(scalars[0] - 1) < 0.02)
    }

    @Test
    func packedIreWeightIsOpaque() throws {
        let packed = try #require(
            FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: 1,
                colorModeCode: Int(ColorMode.dLog2.rawValue),
                iso: 1600))
        let size = FeedEffectsWire.falseColorCubeSize
        #expect(packed.count == size * size * size * 4)
        #expect(packed[0] == 255)
        #expect(packed[4] == 255)
        #expect(packed[packed.count - 4] == 255)
    }

    @Test
    func packedLimitsWeightHasHoles() throws {
        let packed = try #require(
            FeedEffectsWire.packedFalseColorWeight(
                scaleOrdinal: 2,
                colorModeCode: Int(ColorMode.dLog2.rawValue),
                iso: 1600))
        let opaque = packed.enumerated().filter { $0.offset % 4 == 0 }.filter { $0.element == 255 }
            .count
        let clear = packed.enumerated().filter { $0.offset % 4 == 0 }.filter { $0.element == 0 }
            .count
        #expect(opaque > 0)
        #expect(clear > 0)
    }
}

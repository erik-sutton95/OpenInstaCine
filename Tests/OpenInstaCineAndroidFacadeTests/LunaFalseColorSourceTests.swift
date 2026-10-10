import OpenCineMedia
import OpenInstaCineAndroidFacade
import OpenInstaViewCore
import Testing

@Suite struct LunaFalseColorSourceTests {
    @Test func actualIlogWireUsesTheLunaProfileAndSharedPaintProducer() throws {
        let code = Int(ColorMode.iLog.rawValue)
        let paint = try #require(FeedEffectsWire.packedFalseColorPaint(scaleOrdinal: 5,
            colorModeCode: code, iso: 0))
        let expected = MonitorFalseColorLattice.signal(scale: .ire, transfer: .ilog,
            clipByte: 255, lookCurve: LunaMonitorColorProfile.value.rec709LookCurves[.ilog],
            readThroughLook: true, size: FeedEffectsWire.falseColorCubeSize).packedCube(.paint)
        let matches = paint.elementsEqual(expected)
        #expect(matches)
        let signal = try #require(FeedEffectsWire.packedFalseColorPaint(scaleOrdinal: 1,
            colorModeCode: code, iso: 0))
        #expect(!paint.elementsEqual(signal))
    }
}

import OpenCineMedia
import OpenInstaCineAndroidFacade
import OpenInstaViewCore
import Testing

@Suite struct LunaFalseColorSourceTests {
    @Test func ilogWireOnTheLunaProfileUsesTheSharedPaintProducer() throws {
        let code = Int(ColorMode.iLog.rawValue)
        let paint = try #require(MonitorFeedEffectsWire.packedFalseColorPaint(scaleOrdinal: 5,
            colorModeCode: code, iso: 0, sourceProfile: LunaMonitorColorProfile.value))
        let expected = MonitorFalseColorLattice.signal(scale: .ire, transfer: .ilog,
            clipByte: 255, lookCurve: LunaMonitorColorProfile.value.rec709LookCurves[.ilog],
            readThroughLook: true, size: MonitorFeedEffectsWire.falseColorCubeSize).packedCube(.paint)
        let matches = paint.elementsEqual(expected)
        #expect(matches)
        let signal = try #require(MonitorFeedEffectsWire.packedFalseColorPaint(scaleOrdinal: 1,
            colorModeCode: code, iso: 0, sourceProfile: LunaMonitorColorProfile.value))
        #expect(!paint.elementsEqual(signal))
    }
}

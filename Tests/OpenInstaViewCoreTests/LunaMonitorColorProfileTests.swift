import OpenInstaViewCore
import Testing

@Suite struct LunaMonitorColorProfileTests {
    @Test func actualLunaSourceHasOnlyItsIlogLookAndNoDjiPreviewCalibration() {
        let source = LunaMonitorColorProfile.value
        #expect(source.clip.calibrations.isEmpty)
        #expect(source.clip.defaultISO == nil)
        #expect(Set(source.rec709LookCurves.keys) == [.ilog])
        #expect(source.rec709LookCurves[.ilog]?.count == 33)
        #expect(OpenInstaViewCore.ScopeExposureCeiling().resolvedISO() == nil)
        #expect(LiveColorScience.rec709LookCurve(.dlog2) == nil)
        #expect(!LiveColorScience.readsThroughLook(transfer: .dlog2, rec709: true))
        #expect(LiveColorScience.readsThroughLook(transfer: .ilog, rec709: true))
    }
}

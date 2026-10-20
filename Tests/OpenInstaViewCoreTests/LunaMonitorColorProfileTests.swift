import Insta360Protocol
import OpenInstaViewCore
import Testing

@Suite struct LunaMonitorColorProfileTests {
    @Test func actualLunaSourceHasOnlyItsIlogLookAndIlogClipAndNoDjiPreviewCalibration() {
        let source = LunaMonitorColorProfile.value
        #expect(source.clip == LunaScopeClip.profile)
        #expect(Set(source.clip.calibrations.keys) == [.ilog])
        let ceiling = LunaScopeExposureCeiling()
        #expect(ceiling.clipByte(transfer: .ilog, iso: 100) == 205)
        #expect(ceiling.clipByte(transfer: .ilog, iso: 400) == 248)
        #expect(ceiling.clipByte(transfer: .rec709, iso: 100) == 255)
        #expect(Set(source.rec709LookCurves.keys) == [.ilog])
        #expect(source.rec709LookCurves[.ilog]?.count == 33)
        // Luna reports ISO 0 in Auto; until a report the ceiling assumes the lowest ISO.
        #expect(OpenInstaViewCore.ScopeExposureCeiling().resolvedISO() == 100)
        #expect(LiveColorScience.rec709LookCurve(.dlog2) == nil)
        #expect(!LiveColorScience.readsThroughLook(transfer: .dlog2, rec709: true))
        #expect(LiveColorScience.readsThroughLook(transfer: .ilog, rec709: true))
    }
}

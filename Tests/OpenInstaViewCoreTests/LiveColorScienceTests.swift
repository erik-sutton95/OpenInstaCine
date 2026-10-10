import Testing
import OpenCineDJI

@testable import OpenInstaViewCore

/// Original mixed-source look goldens now declare their DJI facts explicitly.
/// Actual Luna-only input checks are separate below.
@Suite struct LiveColorScienceTests {
    private let ceiling = DJIScopeExposureCeiling()

    private func percent(_ c: Double, _ transfer: MonitorTransfer, iso: Int? = nil) -> Double {
        ScopeDisplayScale.monitorPercent(
            c, transfer: transfer, clipByte: ceiling.clipByte(transfer: transfer, iso: iso))
    }

    @Test func videoAndIreReadLogAsTheOperatorChooses() {
        func ire(_ linear: Double, _ transfer: MonitorTransfer, rec709: Bool) -> Double {
            let read = LiveColorScience.falseColorReading(
                encoded: LiveColorScience.encode(linear, transfer: transfer), transfer: transfer,
                rec709: rec709, sourceProfile: DJIMonitorColorProfile.value)
            return percent(read.encoded, read.transfer)
        }
        func label(_ value: Double) -> String? {
            LiveColorScience.falseColorBand(value: value, scale: .ire, transfer: .rec709)?.label
        }
        // 709: DJI's official looks put 18% grey at 38–41 IRE and +1 stop at 53–54.
        for transfer in [MonitorTransfer.dlog2, .dlog, .dlogm] {
            #expect(label(ire(0.18, transfer, rec709: true)) == "18%MG", "\(transfer) 709 grey")
            #expect(label(ire(0.36, transfer, rec709: true)) == "MG+1", "\(transfer) 709 +1")
        }
        // LOG: the signal, like WAVE, so D-Log2 grey (~30) is a gap.
        #expect(label(ire(0.18, .dlog2, rec709: false)) == nil)
        // Curves without an official look always read the signal.
        #expect(LiveColorScience.rec709LookIRE(encoded: 0.5, transfer: .rec709, sourceProfile: DJIMonitorColorProfile.value) == nil)
        #expect(!LiveColorScience.readsThroughLook(transfer: .rec709, rec709: true, sourceProfile: DJIMonitorColorProfile.value))
        #expect(LiveColorScience.readsThroughLook(transfer: .dlog2, rec709: true, sourceProfile: DJIMonitorColorProfile.value))
        // The bundled I-Log cube is this app's own look; DJI's catalog has none.
        #expect(LiveColorScience.rec709LookCurve(.ilog)?.count == 33)
        #expect(DJILook.rec709LookCurve(.ilog) == nil)
        #expect(LiveColorScience.readsThroughLook(transfer: .ilog, rec709: true))
    }

    @Test func cineStopAt709KeepsSceneStopsAndClipsWhereTheLookClips() {
        let clip = ceiling.clipByte(transfer: .dlog2)
        let log = LiveColorScience.falseColorClip(
            scale: .sceneStops, transfer: .dlog2, rec709: false, clipByte: clip, sourceProfile: DJIMonitorColorProfile.value)
        let look = LiveColorScience.falseColorClip(
            scale: .sceneStops, transfer: .dlog2, rec709: true, clipByte: clip, sourceProfile: DJIMonitorColorProfile.value)
        #expect(look.transfer == .dlog2, "CineStop stays on scene stops at 709")
        #expect(look.ceiling < log.ceiling, "the Rec.709 look saturates before the sensor")
        let bands = LiveColorScience.falseColorBands(
            .sceneStops, transfer: look.transfer, clipEncoded: look.ceiling)
        #expect(bands.contains { $0.label == "highlights" }, "light gray still sits above +2")
        let read = LiveColorScience.falseColorReading(
            encoded: 0.5, transfer: .dlog2, rec709: true, scale: .sceneStops, sourceProfile: DJIMonitorColorProfile.value)
        #expect(read.encoded == 0.5 && read.transfer == .dlog2)
    }

    /// Android `FalseColorBands.LOOK_SATURATION` mirrors these; change both together.
    @Test func cineStopAt709ClipMatchesTheAndroidMirror() {
        let android: [MonitorTransfer: Double] = [.dlog2: 30.0 / 32, .dlog: 1, .dlogm: 1]
        for (transfer, expected) in android {
            let clip = LiveColorScience.falseColorClip(
                scale: .sceneStops, transfer: transfer, rec709: true,
                clipByte: ceiling.clipByte(transfer: transfer), sourceProfile: DJIMonitorColorProfile.value)
            #expect(clip.ceiling == expected, "\(transfer)")
        }
        for transfer in [MonitorTransfer.rec709, .hdr] {
            #expect(!LiveColorScience.readsThroughLook(transfer: transfer, rec709: true, sourceProfile: DJIMonitorColorProfile.value))
        }
    }
}

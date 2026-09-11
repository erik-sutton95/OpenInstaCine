import Foundation
import MonitorCore
import Testing

@Suite struct ILogColorScienceTests {
    @Test func paperReflectanceAnchorsUseTheNormalizedTenBitAxis() {
        // Insta360 I-Log white paper, June 2026, printed p3 / physical PDF p5.
        // The paper's integer code values are rounded, not additional precision.
        let fixtures: [(linear: Double, encoded: Double, code: Int)] = [
            (0, 0.09055934, 93),
            (0.18, 0.4220033397148445, 432),
            (22, 0.9999994560172779, 1023),
        ]
        for fixture in fixtures {
            let encoded = MonitorTransfer.ilog.encodeLinear(fixture.linear)
            #expect(abs(encoded - fixture.encoded) < 1e-12)
            #expect(Int((encoded * 1023).rounded()) == fixture.code)
        }
        // Feeding the published code directly must not apply 64...940 expansion.
        #expect(abs(MonitorTransfer.ilog.linearize(432.0 / 1023) - 0.180444251052167) < 1e-12)
        #expect(abs(MonitorTransfer.ilog.linearize(93.0 / 1023) - 0.0000605275727515668) < 1e-12)
    }

    @Test func exactPublishedBranchChoicesAndRoundingArePreserved() {
        let forwardThreshold = 0.01104854
        let atForward = MonitorTransfer.ilog.encodeLinear(forwardThreshold)
        let aboveForward = MonitorTransfer.ilog.encodeLinear(forwardThreshold.nextUp)
        #expect(abs(atForward - 0.15440192831901123) < 1e-14)
        #expect(abs(aboveForward - 0.15440193077978148) < 1e-14)
        #expect(aboveForward > atForward)

        let inverseThreshold = 0.154402
        let belowInverse = MonitorTransfer.ilog.linearize(inverseThreshold.nextDown)
        let atInverse = MonitorTransfer.ilog.linearize(inverseThreshold)
        #expect(abs(belowInverse - 0.011048552405046427) < 1e-14)
        #expect(abs(atInverse - 0.011048551979189218) < 1e-14)
        // The tiny downward step is a property of the supplied rounded constants.
        #expect(belowInverse > atInverse)
        #expect(belowInverse - atInverse < 1e-9)
    }

    @Test func bothBranchesRoundTripAcrossShadowsAndHighlights() {
        let samples: [Double] = [
            0, 0.00001, 0.001, 0.01, 0.01104854, 0.01104854.nextUp,
            0.01104855, 0.01105, 0.02, 0.18, 1, 2, 4, 8, 16, 22,
        ]
        for linear in samples {
            let encoded = MonitorTransfer.ilog.encodeLinear(linear)
            let restored = MonitorTransfer.ilog.linearize(encoded)
            #expect(abs(restored - linear) < 1e-8)
        }
    }

    @Test func peakAndMonitoringClampsRemainSeparateFromPaperRounding() {
        let transfer = MonitorTransfer.ilog
        #expect(abs(transfer.peakLinear - 22.0000984415578) < 1e-10)
        #expect(transfer.peakLinear == transfer.linearize(1))
        #expect(abs(transfer.encodeLinear(transfer.peakLinear) - 1) < 1e-14)
        // These are the existing shared monitoring API's clamps, not the raw formula.
        #expect(transfer.linearize(0) == 0)
        #expect(transfer.linearize(-1) == 0)
        #expect(transfer.linearize(2) == transfer.peakLinear)
        #expect(transfer.encodeLinear(-1) == transfer.encodeLinear(0))
        #expect(transfer.encodeLinear(100) == 1)
    }

    @Test func scopesUsePaperAnchorsWithoutTheMeasuredDjiEiCeilings() {
        for iso in [50, 100, 400, 1600, 6400, 102400] {
            let anchors = ScopeAnchors.make(transfer: .ilog, iso: iso)
            #expect(abs(anchors.black - 0.09055934) < 1e-12)
            #expect(abs(anchors.mid - 0.4220033397148445) < 1e-12)
            #expect(anchors.clip == 1)
            #expect(anchors.clipEdgeByte == 255)
            #expect(ScopeExposureCeiling.clipByte(transfer: .ilog, iso: iso) == 255)
            #expect(ScopeDisplayScale.monitorPercent(anchors.black, transfer: .ilog, iso: iso) == 0)
            #expect(abs(ScopeDisplayScale.monitorPercent(anchors.mid, transfer: .ilog, iso: iso) - 42.20033397148445) < 1e-10)
            #expect(ScopeDisplayScale.monitorPercent(1, transfer: .ilog, iso: iso) == 100)
        }
        let observation = ScopeExposureCeiling.observeTapMax(247, transfer: .ilog)
        #expect(observation.clip == 255)
        #expect(!observation.maxRose)
    }

    @Test func exposureUsesDecodedBt2020Channels() {
        let transfer = MonitorTransfer.ilog
        let w = LiveColorScience.lumaWeights(transfer)
        #expect(w.red == 0.2627 && w.green == 0.6780 && w.blue == 0.0593)
        let red = transfer.encodeLinear(1)
        let green = transfer.encodeLinear(0)
        let blue = transfer.encodeLinear(0.18)
        let luminance = LiveColorScience.linearLuminance(
            red: red, green: green, blue: blue, transfer: transfer)
        #expect(abs(luminance - (0.2627 + 0.0593 * 0.18)) < 1e-12)
        let inverseOfEncodedLuma = transfer.linearize(w.red * red + w.green * green + w.blue * blue)
        #expect(abs(luminance - inverseOfEncodedLuma) > 0.05)
        #expect(abs(LiveColorScience.stops(encoded: transfer.encodeLinear(0.18), transfer: transfer)) < 1e-12)
    }

    @Test func transferIdentityAppendsWithoutChangingExistingCases() {
        #expect(MonitorTransfer.allCases == [.rec709, .hdr, .dlog, .dlog2, .ilog])
        #expect(MonitorTransfer.ilog.rawValue == "ilog")
        #expect(MonitorTransfer.ilog.label == "I-Log")
    }
}

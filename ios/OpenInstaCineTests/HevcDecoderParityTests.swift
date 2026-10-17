import OpenCineApple
import OpenCineMedia
import XCTest

@testable import OpenInstaCine

/// SIMULATED host values exercise the actual app decoder and retained native demand.
@MainActor
final class HevcDecoderParityTests: XCTestCase {
    func testEffectsAndProviderPreserveIndependentPreviewDemand() {
        let decoder = HevcDecoder()
        defer { decoder.close() }
        decoder.needsWatchPreview = true
        var effects = OpenCineMedia.MonitorFrameEffects()
        effects.histogram = true
        effects.faceAF = true
        decoder.effects = effects
        XCTAssertTrue(decoder.demand.assists.histogram)
        XCTAssertTrue(decoder.demand.decodedSource)
        XCTAssertTrue(decoder.demand.externalPreview)

        effects.histogram = false
        effects.faceAF = false
        effects.inspectorSample = true
        decoder.effectsProvider = { effects }
        let supplied = decoder.demandProvider?()
        XCTAssertEqual(decoder.effects, effects)
        XCTAssertEqual(supplied?.assists.histogram, false)
        XCTAssertEqual(supplied?.decodedSource, true)
        XCTAssertEqual(supplied?.externalPreview, true)
        decoder.needsWatchPreview = false
        XCTAssertTrue(decoder.demand.decodedSource)
        XCTAssertFalse(decoder.demand.externalPreview)
    }

    func testMissingColorReportPreservesTheAcceptedTransfer() {
        let decoder = HevcDecoder()
        defer { decoder.close() }
        decoder.incomingColorMode = .normal
        XCTAssertEqual(decoder.incomingTransfer, .rec709)
        decoder.incomingColorMode = nil
        XCTAssertEqual(decoder.incomingTransfer, .rec709)
        decoder.incomingColorMode = .hdr
        XCTAssertEqual(decoder.incomingTransfer, .hdr)
    }

    func testTerminalCloseClearsHostProvidersAndCannotReopen() {
        let decoder = HevcDecoder()
        decoder.effectsProvider = { .init() }
        decoder.close()
        XCTAssertNil(decoder.effectsProvider)
        XCTAssertNil(decoder.sourceToken)
        decoder.reset()
        decoder.startSimulatorSampleIfNeeded()
        XCTAssertNil(decoder.sourceToken)
    }

    func testInitialDemandRetainsTheExistingUnboundSourcePolicy() {
        let decoder = HevcDecoder()
        defer { decoder.close() }
        XCTAssertFalse(decoder.demand.assists.allowsTransferInference)
        decoder.effects = .init()
        XCTAssertTrue(decoder.demand.assists.allowsTransferInference)
    }

    func testBindingWithoutCalibrationLeavesSourceISOUnknown() {
        let decoder = HevcDecoder()
        defer { decoder.close() }
        let samples = LiveFrameSampleBus(profile: LiveAssistEngine.configuration.clipProfile)
        decoder.bindSourcePublication(samples)
        XCTAssertNil(samples.exposureCeiling.resolvedISO())
        XCTAssertNil(decoder.sourceCalibrationProvider)
        XCTAssertFalse(decoder.refreshSourceCalibration())
        XCTAssertNil(samples.exposureCeiling.resolvedISO())
    }
}

import CoreVideo
import OpenCineApple
import OpenCineMedia
import XCTest
@testable import OpenInstaCine

@MainActor final class ScopePublicationOwnershipTests: XCTestCase {
    func testRetiredDecoderCannotResetSuccessorSamples() {
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        let retired = HevcDecoder()
        retired.sampleBus = bus
        let successor = bus.openSource(.live)
        successor.exposureCeiling.setISO(800)
        let held = ScopeAssistBundle(revision: 2, clipByte: 231)
        XCTAssertTrue(bus.publish(successor, source: nil, transfer: .dlog2, bundle: held))
        retired.reset()
        XCTAssertEqual(bus.bundle, held)
        XCTAssertTrue(bus.isCurrent(successor))
        XCTAssertEqual(successor.exposureCeiling.resolvedISO(), 800)
    }
    func testLatePlaybackPublicationAndCloseCannotChangeSuccessorOrLiveSource() {
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        let live = bus.openSource(.live)
        let liveFrame = ScopeAssistBundle(revision: 1, clipByte: 247)
        XCTAssertTrue(bus.publish(live, source: nil, transfer: .dlog2, bundle: liveFrame))
        let retired = bus.openSource(.playback)
        XCTAssertEqual(bus.displayBundle, .empty, "A clip without a frame must not show live scope data")
        let successor = bus.openSource(.playback)
        let held = ScopeAssistBundle(revision: 3, clipByte: 200)
        XCTAssertTrue(bus.publish(successor, source: nil, transfer: .dlog2, bundle: held))
        XCTAssertFalse(bus.publish(retired, source: nil, transfer: .rec709, bundle: .empty))
        bus.closeSource(retired)
        XCTAssertEqual(bus.displayBundle, held)
        XCTAssertTrue(bus.usesPlaybackSource)
        bus.closeSource(successor)
        XCTAssertEqual(bus.displayBundle, liveFrame)
        XCTAssertFalse(bus.usesPlaybackSource)
    }
    func testPlaybackAndReplacementOwnIndependentCalibrationHistory() {
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        let live = bus.openSource(.live)
        live.exposureCeiling.setISO(800)
        let held = ScopeAssistBundle(revision: 1, clipByte: 231)
        XCTAssertTrue(bus.publish(live, source: nil, transfer: .dlog2, bundle: held))
        let playback = bus.openSource(.playback)
        playback.exposureCeiling.setISO(400)
        XCTAssertEqual(live.exposureCeiling.clipByte(transfer: .dlog2), 231)
        bus.closeSource(playback)
        XCTAssertEqual(bus.exposureCeiling.resolvedISO(), 800)
        let successor = bus.openSource(.live)
        XCTAssertEqual(successor.exposureCeiling.resolvedISO(), 1600)
        successor.exposureCeiling.setISO(3200)
        live.exposureCeiling.reset()
        XCTAssertEqual(successor.exposureCeiling.resolvedISO(), 3200)
        XCTAssertEqual(held.clipByte, 231)
    }
    func testLiveCalibrationCannotRetuneTheDisplayedClip() throws {
        let bus = LiveFrameSampleBus(profile: .init(defaultISO: 1600))
        let runtime = HevcDecoder()
        runtime.sampleBus = bus
        defer { runtime.close() }
        let live = bus.exposureCeiling
        let playback = bus.openSource(.playback)
        playback.exposureCeiling.setISO(400)
        let source = try XCTUnwrap(runtime.sourceToken)
        XCTAssertTrue(runtime.updateSourceCalibration(iso: 6400, source: source))
        XCTAssertEqual(live.resolvedISO(), 6400)
        XCTAssertEqual(playback.exposureCeiling.resolvedISO(), 400)
    }

    func testUnknownOrInvalidReportsPreserveTheLiveCalibration() throws {
        let bus = LiveFrameSampleBus(profile: .init(defaultISO: 1600))
        let runtime = HevcDecoder()
        let source = try XCTUnwrap(runtime.sourceToken)
        XCTAssertFalse(runtime.updateSourceCalibration(iso: 800, source: source))
        runtime.sampleBus = bus
        defer { runtime.close() }
        let live = bus.exposureCeiling
        XCTAssertTrue(runtime.updateSourceCalibration(iso: 800, source: source))
        for iso: Int? in [nil, 0, 49, 102_401] {
            XCTAssertFalse(runtime.updateSourceCalibration(iso: iso, source: source))
            XCTAssertEqual(live.resolvedISO(), 800)
        }
        XCTAssertFalse(runtime.updateSourceCalibration(iso: 3200, source: nil))
        XCTAssertEqual(live.resolvedISO(), 800)
    }

    func testRetiredAndReplacedRuntimeReportsCannotRetuneTheSuccessor() throws {
        let bus = LiveFrameSampleBus(profile: .init(defaultISO: 1600))
        let retired = HevcDecoder()
        retired.sampleBus = bus
        let oldSource = try XCTUnwrap(retired.sourceToken)
        let successor = HevcDecoder()
        successor.sampleBus = bus
        defer { retired.close(); successor.close() }
        let currentSource = try XCTUnwrap(successor.sourceToken)
        let live = bus.exposureCeiling
        XCTAssertTrue(successor.updateSourceCalibration(iso: 3200, source: currentSource))
        XCTAssertFalse(retired.updateSourceCalibration(iso: 800, source: oldSource))
        XCTAssertFalse(successor.updateSourceCalibration(iso: 800, source: oldSource))
        XCTAssertEqual(live.resolvedISO(), 3200)
        successor.reset()
        let replacement = bus.exposureCeiling
        XCTAssertFalse(successor.updateSourceCalibration(iso: 800, source: currentSource))
        XCTAssertEqual(replacement.resolvedISO(), 1600)
        let replacementSource = try XCTUnwrap(successor.sourceToken)
        XCTAssertTrue(successor.updateSourceCalibration(iso: 6400, source: replacementSource))
        successor.close()
        let closedISO = replacement.resolvedISO()
        XCTAssertFalse(successor.updateSourceCalibration(iso: 800, source: replacementSource))
        XCTAssertEqual(replacement.resolvedISO(), closedISO)
    }

}

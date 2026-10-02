import CoreVideo
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

}

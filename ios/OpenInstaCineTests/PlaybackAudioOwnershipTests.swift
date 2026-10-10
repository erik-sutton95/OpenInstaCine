import AVFoundation
import OpenCineApple
import XCTest

@MainActor
final class PlaybackAudioOwnershipTests: XCTestCase {
    func testAbsentSourceIsDistinctFromMeasuredSilence() throws {
        let owner = MonitorAudioPeakAccumulator()
        XCTAssertNil(owner.sampleAndReset())
        let source = try XCTUnwrap(owner.beginSource())
        XCTAssertNil(owner.sampleAndReset())
        XCTAssertTrue(source.ingest(left: 0, right: 0))
        let sample = try XCTUnwrap(owner.sampleAndReset())
        XCTAssertEqual(sample.left, 0)
        XCTAssertEqual(sample.right, 0)
        XCTAssertTrue(source.close())
        XCTAssertNil(owner.sampleAndReset())
    }

    func testRetiredSourceCannotPublishPrepareOrClearSuccessor() throws {
        let owner = MonitorAudioPeakAccumulator()
        let old = try XCTUnwrap(owner.beginSource())
        let queued = try XCTUnwrap(old.prepare())
        let next = try XCTUnwrap(owner.beginSource())
        let writer = try XCTUnwrap(next.prepare())
        XCTAssertTrue(writer.ingest(left: 0.25, right: 0.5))
        XCTAssertFalse(queued.ingest(left: 1, right: 1))
        XCTAssertNil(old.prepare())
        XCTAssertFalse(old.close())
        let sample = try XCTUnwrap(owner.sampleAndReset())
        XCTAssertEqual(sample.left, 0.25)
        XCTAssertEqual(sample.right, 0.5)
        XCTAssertTrue(next.isActive)
    }

    func testReprepareRejectsCapturedFormatAndClearsItsMeasurements() throws {
        let owner = MonitorAudioPeakAccumulator()
        let source = try XCTUnwrap(owner.beginSource())
        let old = try XCTUnwrap(source.prepare())
        XCTAssertTrue(old.ingest(left: 1, right: 1))
        let next = try XCTUnwrap(source.prepare())
        XCTAssertNil(owner.sampleAndReset())
        XCTAssertFalse(old.ingest(left: 1, right: 1))
        XCTAssertTrue(next.ingest(left: 0.1, right: 0.2))
        XCTAssertEqual(try XCTUnwrap(owner.sampleAndReset()).left, 0.1)
    }

    func testTerminalOwnerCannotReopen() throws {
        let owner = MonitorAudioPeakAccumulator()
        let source = try XCTUnwrap(owner.beginSource())
        let writer = try XCTUnwrap(source.prepare())
        owner.close()
        XCTAssertNil(owner.beginSource())
        XCTAssertNil(source.prepare())
        XCTAssertFalse(writer.ingest(left: 1, right: 1))
        XCTAssertFalse(source.close())
        XCTAssertNil(owner.sampleAndReset())
    }

    func testNewSourceAndFormatCannotInheritHeldMeterPeaks() throws {
        let owner = MonitorAudioPeakAccumulator()
        let meter = MonitorAudioMeterSampler(owner: owner)
        let old = try XCTUnwrap(owner.beginSource())
        XCTAssertTrue(old.ingest(left: 1, right: 1))
        XCTAssertEqual(try XCTUnwrap(meter.step(dt: 0.04)).left.peakDB, 0)
        let next = try XCTUnwrap(owner.beginSource())
        XCTAssertTrue(next.ingest(left: 0.1, right: 0.1))
        // A new sample arrives before polling could observe the empty source transition.
        XCTAssertEqual(try XCTUnwrap(meter.step(dt: 0.04)).left.peakDB, -20, accuracy: 0.00001)
        let writer = try XCTUnwrap(next.prepare())
        XCTAssertTrue(writer.ingest(left: 1, right: 1))
        XCTAssertEqual(try XCTUnwrap(meter.step(dt: 0.04)).left.peakDB, 0)
        let changed = try XCTUnwrap(next.prepare())
        XCTAssertTrue(changed.ingest(left: 0.5, right: 0.5))
        XCTAssertEqual(try XCTUnwrap(meter.step(dt: 0.04)).left.peakDB, -6.020599913,
            accuracy: 0.00001)
        next.close()
        XCTAssertNil(meter.step(dt: 0.04))
    }

    func testOutputMuteUsesMeasuredSilenceWithoutRetainingUnmutedHistory() throws {
        let owner = MonitorAudioPeakAccumulator()
        let meter = MonitorAudioMeterSampler(owner: owner)
        let source = try XCTUnwrap(owner.beginSource())
        source.ingest(left: 1, right: 1)
        XCTAssertEqual(try XCTUnwrap(meter.step(dt: 0.04)).left.peakDB, 0)
        meter.reset()
        source.ingest(left: 1, right: 1)
        XCTAssertEqual(try XCTUnwrap(meter.step(dt: 0.04, outputMuted: true)).left.peakDB, -60)
        XCTAssertNil(MonitorAudioMeterSampler(owner: MonitorAudioPeakAccumulator())
            .step(dt: 0.04, outputMuted: true))
    }

    func testActualTapAttachmentDetachAndTerminalClose() async throws {
        let composition = AVMutableComposition()
        _ = try XCTUnwrap(composition.addMutableTrack(withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid))
        let item = AVPlayerItem(asset: composition)
        let runtime = MonitorPlaybackAudioMeterRuntime()
        runtime.attach(to: item)
        let attached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "audioMix != nil"),
            object: item)
        await fulfillment(of: [attached], timeout: 5)
        let mix = try XCTUnwrap(item.audioMix)
        XCTAssertNotNil(mix.inputParameters.first?.audioTapProcessor)
        runtime.detach(from: item)
        XCTAssertNil(item.audioMix)
        runtime.close()
        runtime.attach(to: item)
        XCTAssertNil(item.audioMix, "A closed owner cannot schedule a new track query")
        withExtendedLifetime(mix) {}
    }
}

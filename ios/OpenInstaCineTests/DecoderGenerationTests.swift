import CoreVideo
import OpenCineApple
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

@MainActor
final class DecoderGenerationTests: XCTestCase {
    func testResetRejectsAlreadyQueuedAssistResult() async {
        await assertRejectsQueuedResult { $0.reset() }
    }

    func testPresentationRebuildRejectsAlreadyQueuedAssistResult() async {
        await assertRejectsQueuedResult { _ = $0.rebuildPresentation() }
    }

    func testLateSuccessfulDecodeCannotEnterTheNewGeneration() async {
        let decoder = HevcDecoder()
        let oldGeneration = decoder.sourceFrameGeneration
        _ = decoder.rebuildPresentation()
        let current = ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16)
        let drained = expectation(description: "Current generation reaches processing")
        var identityFrames = 0
        decoder.onIdentityFrame = { _ in identityFrames += 1 }
        decoder.onSourceFrame = { lease in
            XCTAssertTrue(
                lease.pixelBuffer === current, "A late VT success must not reach consumers")
            drained.fulfill()
        }

        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16),
            generation: oldGeneration)
        decoder.handleDecodedFrame(current, isNewSourceFrame: false)
        await fulfillment(of: [drained], timeout: 3)

        XCTAssertEqual(identityFrames, 0, "Stale source must not reach the watcher encoder")
        XCTAssertNil(decoder.lastSourceFrameAt)
    }

    func testCurrentGenerationStillPublishesNewSourceHealthAfterReset() async {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        decoder.sampleBus = bus
        decoder.reset()
        let delivered = expectation(description: "Current source reaches processing")
        decoder.onSourceFrame = { _ in delivered.fulfill() }
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16),
            generation: decoder.sourceFrameGeneration)
        await fulfillment(of: [delivered], timeout: 3)

        XCTAssertNotNil(decoder.lastSourceFrameAt)
        XCTAssertEqual(bus.decodedFrames, 1)
    }

    func testSourceFrameLeaseIsLentForTheCallbackOnly() async {
        let decoder = HevcDecoder()
        let delivered = expectation(description: "Source frame lent")
        var lent: DecodedFrameLease?
        decoder.onSourceFrame = { lease in
            XCTAssertNotNil(lease.pixelBuffer)
            XCTAssertEqual(Int(lease.generation.value), decoder.sourceFrameGeneration)
            lent = lease
            delivered.fulfill()
        }
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 120, width: 16, height: 16))
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertEqual(
            lent?.isReleased, true, "Consumers keep pixels by taking their own reference")
    }

    func testNativeSourceTokenRejectsRetiredEncodedInputBeforeParsing() throws {
        let native = MonitorLiveVideoRuntime()
        let retired = try XCTUnwrap(native.sourceToken)
        native.reset()
        let current = try XCTUnwrap(native.sourceToken)
        XCTAssertEqual(current.stream, retired.stream)
        XCTAssertGreaterThan(current.generation, retired.generation)
        let vps: [UInt8] = [0, 0, 1, 0x40, 0x01]
        XCTAssertFalse(native.decode(accessUnit: vps, source: retired))
        XCTAssertTrue(native.nalTypesSeen.isEmpty, "Retired input cannot set the new source codec or parameter sets")
        _ = native.decode(accessUnit: vps, source: current)
        XCTAssertEqual(native.nalTypesSeen, [32], "Exercise accepted encoded input through the actual parser")
        XCTAssertEqual(native.health.codec, .hevc)
        native.close()
        XCTAssertNil(native.sourceToken)
        native.reset()
        XCTAssertNil(native.sourceToken, "Terminal close cannot silently reactivate an old owner")
        XCTAssertFalse(native.decode(accessUnit: vps, source: current))
    }

    func testNativeCloseReleasesLateFrameLeaseAndPreservesSuccessorPublication() throws {
        let native = MonitorLiveVideoRuntime()
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        native.sampleBus = bus
        let token = try XCTUnwrap(native.sourceToken)
        let lease = DecodedFrameLease(ScopeTestBuffers.makeFlatBuffer(code: 40),
            stream: token.stream, generation: native.health.pipelineGeneration, timeNs: 0)
        let successor = bus.openSource(.live)
        let held = ScopeAssistBundle(revision: 4, clipByte: 231)
        XCTAssertTrue(bus.publish(successor, source: nil, transfer: .dlog2, bundle: held))
        native.close()
        native.submitDecodedFrame(lease, source: token)
        XCTAssertTrue(lease.isReleased)
        XCTAssertEqual(bus.bundle, held)
        XCTAssertTrue(bus.isCurrent(successor))
        XCTAssertNil(native.health.source)
        XCTAssertFalse(native.health.nativeOutputExpected)
        XCTAssertTrue(native.health.displayedImageRemoved)
    }

    func testRetiredPublicationRejectsIdentityTapAndSourceHealth() async {
        let retired = HevcDecoder()
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        retired.sampleBus = bus
        let successor = HevcDecoder()
        successor.sampleBus = bus
        var retiredIdentityFrames = 0
        retired.onIdentityFrame = { _ in retiredIdentityFrames += 1 }
        retired.handleDecodedFrame(ScopeTestBuffers.makeFlatBuffer(code: 40))
        let delivered = expectation(description: "Successor source drains")
        successor.onSourceFrame = { _ in delivered.fulfill() }
        successor.handleDecodedFrame(ScopeTestBuffers.makeFlatBuffer(code: 180))
        await fulfillment(of: [delivered], timeout: 3)
        XCTAssertEqual(retiredIdentityFrames, 0)
        XCTAssertNil(retired.lastSourceFrameAt)
        XCTAssertEqual(bus.decodedFrames, 1)
        XCTAssertEqual(bus.sourcePixelBuffer.map { CVPixelBufferGetWidth($0) }, 128)
    }

    func testClosingRetiredNativeRuntimeCannotHideSuccessorPictureHost() {
        let host = MonitorPictureHost(frame: .zero)
        let retired = MonitorLiveVideoRuntime()
        retired.processedFeed = host
        let successor = MonitorLiveVideoRuntime()
        successor.processedFeed = host
        host.isHidden = false
        retired.close()
        XCTAssertFalse(host.isHidden, "Closing an older owner cannot hide the successor host")
        XCTAssertNotNil(host.onPresented, "The current native owner retains its completion callback")
        successor.close()
        XCTAssertTrue(host.isHidden, "The actual current owner still retires its host")
    }

    private func assertRejectsQueuedResult(_ invalidate: (HevcDecoder) -> Void) async {
        let decoder = HevcDecoder()
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        decoder.sampleBus = bus
        let old = ScopeTestBuffers.makeFlatBuffer(code: 40, width: 16, height: 16)
        let sentinel = ScopeTestBuffers.makeFlatBuffer(code: 180, width: 16, height: 16)
        let drained = expectation(description: "Current cached frame drains assist results")
        var oldFrames = 0
        decoder.onSourceFrame = { lease in
            if lease.pixelBuffer === old { oldFrames += 1 }
            if lease.pixelBuffer === sentinel { drained.fulfill() }
        }

        // No actor yield between source submission and invalidation: an old
        // completion cannot run on MainActor until the lifecycle changes.
        decoder.handleDecodedFrame(old)
        invalidate(decoder)
        decoder.handleDecodedFrame(sentinel, isNewSourceFrame: false)
        await fulfillment(of: [drained], timeout: 3)

        XCTAssertEqual(oldFrames, 0, "An old source must not reach presentation/Face AF")
        XCTAssertNil(decoder.lastSourceFrameAt, "Old pixels must not mark recovery healthy")
        XCTAssertNil(decoder.lastPresentedAt)
        XCTAssertEqual(bus.decodedFrames, 0, "A cached repaint is not a new camera picture")
    }
}

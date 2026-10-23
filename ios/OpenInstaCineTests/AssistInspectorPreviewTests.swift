import CoreImage
import CoreVideo
import OpenCineApple
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

@MainActor
final class AssistInspectorPreviewTests: XCTestCase {
    /// This test's monitored source (XCTest makes a fresh one per test).
    private let ceiling = ScopeExposureCeiling()

    func testInspectorRequestsSamplingWithoutEnablingPictureEffects() {
        let original = LiveImageEffects()
        let image = original.withInspectorDemand(.peaking)
        XCTAssertTrue(image.needsSample)
        XCTAssertFalse(image.needsGPUFeed)
        XCTAssertFalse(image.needsScopes)
        XCTAssertFalse(image.faceAF)
        XCTAssertFalse(image.peaking)
        XCTAssertFalse(original.needsSample)

        var activeHistogram = original
        activeHistogram.histogram = true
        let scope = activeHistogram.withInspectorDemand(.waveform)
        XCTAssertEqual(scope.activeScopeCount, 2)
        XCTAssertTrue(scope.histogram)
        XCTAssertTrue(scope.waveform)
        XCTAssertFalse(scope.needsGPUFeed)
    }

    func testScopeDemandBelongsToTheVisibleSourceAndEndsOnDismiss() {
        let assist = LiveAssistState()
        assist.waveform = false
        assist.configureTool = .waveform
        XCTAssertFalse(assist.isOn(.waveform))
        XCTAssertFalse(assist.isVisible(.waveform))
        XCTAssertTrue(assist.effects.waveform)
        XCTAssertFalse(assist.playbackEffects.waveform)
        assist.gradesClip = true
        XCTAssertFalse(assist.effects.waveform, "Playback must not demand a hidden live scope")
        XCTAssertTrue(assist.playbackEffects.waveform)
        assist.configureTool = nil
        XCTAssertFalse(assist.effects.waveform)
        XCTAssertFalse(assist.playbackEffects.waveform)
    }

    func testCoveredLiveDropsScopeDemandButKeepsPictureEffects() {
        let assist = LiveAssistState()
        assist.clean = false
        assist.waveform = true
        assist.trafficLights = true
        assist.peaking = true
        assist.liveCovered = true
        XCTAssertFalse(assist.effects.needsScopes)
        XCTAssertTrue(assist.effects.peaking, "Looks keep their demand beneath pages")
        XCTAssertTrue(assist.effects.needsSample)
        assist.liveCovered = false
        XCTAssertTrue(assist.effects.waveform)
        XCTAssertTrue(assist.effects.trafficLights)
    }

    func testImageSamplingBelongsToTheActiveInspectorAndStopsWhenInactive() {
        let assist = LiveAssistState()
        assist.configureTool = .peaking
        XCTAssertTrue(assist.effects.inspectorSample)
        XCTAssertFalse(assist.playbackEffects.inspectorSample)
        assist.gradesClip = true
        XCTAssertFalse(assist.effects.inspectorSample)
        XCTAssertTrue(assist.playbackEffects.inspectorSample)
        assist.inspectorSceneActive = false
        XCTAssertFalse(assist.effects.inspectorSample)
        XCTAssertFalse(assist.playbackEffects.inspectorSample)
        assist.configureTool = .waveform
        assist.waveform = false
        assist.playbackVisibleTools = []
        XCTAssertFalse(assist.effects.waveform)
        XCTAssertFalse(assist.playbackEffects.waveform)
        assist.inspectorSceneActive = true
        XCTAssertTrue(assist.playbackEffects.waveform)
        XCTAssertFalse(assist.effects.waveform)
    }

    func testImagePreviewForcesOnlyTheSelectedWarningWithoutChangingMainEnablement() {
        let assist = LiveAssistState()
        assist.peaking = false
        assist.falseColor = false
        assist.zebra = true
        let preview = AssistInspectorPreviewPolicy.imageEffects(
            assist: assist, tool: .peaking, transfer: .dlog2, ceiling: ceiling)
        XCTAssertTrue(preview.peaking)
        XCTAssertFalse(preview.zebra)
        XCTAssertFalse(preview.falseColor)
        XCTAssertEqual(preview.colorMode, .dLog2)
        XCTAssertFalse(preview.inspectorSample)
        XCTAssertFalse(assist.peaking)
        XCTAssertTrue(assist.zebra)
    }

    func testRetiredSourceCannotPublishThroughNativeInspectorOwner() async throws {
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        let firstLease = bus.openSource(.live)
        bus.publish(firstLease, source: try Self.buffer(width: 8, height: 8), transfer: .dlog2, bundle: nil)
        let frame = try XCTUnwrap(bus.inspectorFrame)
        let started = InspectorPreviewTestSignal("Native inspector accepted source A")
        let release = DispatchSemaphore(value: 0)
        let clock = InspectorPreviewTestClock()
        let reference = try Self.referenceImage()
        let renderer = MonitorInspectorImageRenderer(now: { clock.now }, operation: { _, _ in
            started.signal()
            XCTAssertEqual(release.wait(timeout: .now() + 10), .success)
            return reference
        }, workerQoS: inspectorTestWorkerQoS)
        let owner = UUID()
        renderer.activate(owner: owner)
        let work = Task { await renderer.render(owner: owner, source: frame) { LiveImageEffects() } }
        defer { work.cancel(); release.signal() }
        try await started.wait()
        let successor = bus.openSource(.live)
        bus.publish(successor, source: try Self.buffer(width: 16, height: 8), transfer: .rec709, bundle: nil)
        release.signal()
        let retired = await work.value
        XCTAssertNil(retired, "Retiring the actual source must discard native work without a view callback")
        XCTAssertFalse(frame.isCurrent)
        XCTAssertEqual(bus.inspectorFrame?.transfer, .rec709)
        clock.now = 200_000_000
        release.signal()
        let resumed = await renderer.render(owner: owner, source: try XCTUnwrap(bus.inspectorFrame)) { LiveImageEffects() }
        XCTAssertNotNil(resumed, "A successor source reuses the retained native worker")
    }

    func testCoveredLiveFrameCannotReachInspectorEvenWhileItsLeaseIsActive() async throws {
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        let live = bus.openSource(.live)
        bus.publish(live, source: try Self.buffer(width: 8, height: 8), transfer: .rec709, bundle: nil)
        let frame = try XCTUnwrap(bus.inspectorFrame)
        let renderer = MonitorInspectorImageRenderer(workerQoS: inspectorTestWorkerQoS)
        let owner = UUID()
        renderer.activate(owner: owner)
        let playback = bus.openSource(.playback)
        XCTAssertTrue(live.isActive)
        XCTAssertNil(bus.inspectorFrame, "A cold playback source cannot borrow the hidden camera picture")
        var preparations = 0
        let hidden = await renderer.render(owner: owner, source: frame) {
            preparations += 1
            return LiveImageEffects()
        }
        XCTAssertNil(hidden)
        XCTAssertEqual(preparations, 0, "Refused source work cannot prepare an inspector cube")
        bus.closeSource(playback)
        let stale = await renderer.render(owner: owner, source: frame) { LiveImageEffects() }
        XCTAssertNil(stale, "Returning live cannot revive a previously captured source epoch")
        let current = try XCTUnwrap(bus.inspectorFrame)
        let resumed = await renderer.render(owner: owner, source: current) { LiveImageEffects() }
        XCTAssertNotNil(resumed)
        let result = try XCTUnwrap(resumed)
        bus.closeSource(live)
        XCTAssertFalse(renderer.isCurrent(result), "A completed native result loses authority with its actual source")
    }

    func testPreviewImageIsBoundedBeforeRendering() async throws {
        let renderer = MonitorInspectorImageRenderer(workerQoS: inspectorTestWorkerQoS)
        let owner = UUID()
        renderer.activate(owner: owner)
        let buffer = try Self.buffer(width: 640, height: 360)
        let result = await renderer.render(
            owner: owner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertEqual(result?.image.width, 320)
        XCTAssertEqual(result?.image.height, 180)
    }

    func testObservedPreviewOptionsIncludeDisabledPictureToolSettings() {
        let assist = LiveAssistState()
        assist.lutEnabled = false
        assist.splitComparison = false
        let beforeSplit = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .lut, transfer: .rec709, ceiling: ceiling)
        assist.splitComparison = true
        let afterSplit = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .lut, transfer: .rec709, ceiling: ceiling)
        XCTAssertNotEqual(beforeSplit, afterSplit)
        XCTAssertTrue(afterSplit.splitComparison)
        XCTAssertEqual(afterSplit.lutDimension, 0, "Observation must not prepare a preview LUT")

        assist.desqueezeFactor = 1.33
        let beforeStretch = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .desqueeze, transfer: .rec709, ceiling: ceiling)
        assist.desqueezeFactor = 2
        let afterStretch = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .desqueeze, transfer: .rec709, ceiling: ceiling)
        XCTAssertNotEqual(beforeStretch, afterStretch)
        XCTAssertEqual(afterStretch.desqueezeFactor, 2)
    }

    func testLUTPreviewResolvesTheSelectedLookWhileMainLUTRemainsOff() {
        let assist = LiveAssistState()
        assist.lutEnabled = false
        assist.lutSelection = .creativeMono
        assist.refreshLUTCube()
        assist.configureTool = .lut
        XCTAssertEqual(assist.effects.lutDimension, 0)
        let preview = AssistInspectorPreviewPolicy.imageEffects(
            assist: assist, tool: .lut, transfer: .rec709, ceiling: ceiling)
        XCTAssertGreaterThan(preview.lutDimension, 1)
        XCTAssertFalse(preview.lutRGBA.isEmpty)
        XCTAssertFalse(assist.lutEnabled)
        XCTAssertEqual(assist.effects.lutDimension, 0)
        assist.configureTool = nil
        XCTAssertFalse(assist.effects.inspectorSample)
    }

    func testBusyPreviewDropsNewWorkAndCancelledWorkCannotPublish() async throws {
        let started = InspectorPreviewTestSignal("First image work started")
        let release = DispatchSemaphore(value: 0)
        let invocations = InspectorRenderInvocationCounter()
        let clock = InspectorPreviewTestClock()
        let reference = try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let renderer = MonitorInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                if invocations.increment() == 1 {
                    started.signal()
                    XCTAssertEqual(
                        release.wait(timeout: .now() + 10), .success,
                        "Test did not release the first worker; a rejected request may have queued")
                }
                return reference
            }, workerQoS: inspectorTestWorkerQoS)
        let owner = UUID()
        let remountedOwner = UUID()
        renderer.activate(owner: owner)
        let buffer = try Self.buffer(width: 8, height: 8)
        let first = Task {
            await renderer.render(owner: owner, source: buffer, effects: { LiveImageEffects() })
        }
        defer {
            first.cancel()
            release.signal()
        }
        try await started.wait()
        let dropped = await renderer.render(
            owner: owner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertNil(dropped, "A busy preview must not retain a queued second source")
        XCTAssertEqual(invocations.value, 1, "Dropped work must never enter the renderer")
        first.cancel()
        renderer.deactivate(owner: owner)
        renderer.activate(owner: remountedOwner)
        clock.now = 200_000_000
        let remounted = await renderer.render(
            owner: remountedOwner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertNil(remounted, "Cancellation/remount must not release the running operation")
        XCTAssertEqual(invocations.value, 1)
        release.signal()
        let cancelled = await first.value
        XCTAssertNil(cancelled, "Dismissed inspectors must never adopt completed stale work")
        XCTAssertEqual(invocations.value, 1, "Cancellation must not drain queued work")

        let resumed = await renderer.render(
            owner: remountedOwner, source: buffer, effects: { LiveImageEffects() })
        XCTAssertNotNil(resumed, "Cancellation must release admission for the next inspector")
        XCTAssertEqual(
            invocations.value, 2, "Exactly one fresh request is admitted after cancellation")
    }

    func testRapidInspectorSwitchesKeepTheOriginalAdmissionClock() async throws {
        let clock = InspectorPreviewTestClock()
        let invocations = InspectorRenderInvocationCounter()
        var preparations = 0
        let prepare: @MainActor @Sendable () -> LiveImageEffects = {
            preparations += 1
            return LiveImageEffects()
        }
        let reference = try Self.referenceImage()
        let renderer = MonitorInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                _ = invocations.increment()
                return reference
            }, workerQoS: inspectorTestWorkerQoS)
        let buffer = try Self.buffer(width: 8, height: 8)
        let firstOwner = UUID()
        renderer.activate(owner: firstOwner)
        let first = await renderer.render(
            owner: firstOwner, source: buffer, effects: prepare)
        XCTAssertNotNil(first)
        renderer.deactivate(owner: firstOwner)
        let earlyTimes: [UInt64] = [20_000_000, 80_000_000, 120_000_000, 199_999_999]
        for time in earlyTimes {
            clock.now = time
            let owner = UUID()
            renderer.activate(owner: owner)
            let result = await renderer.render(
                owner: owner, source: buffer, effects: prepare)
            XCTAssertNil(result, "Tab changes must not restart the 200 ms budget")
            renderer.deactivate(owner: owner)
        }
        XCTAssertEqual(invocations.value, 1)
        XCTAssertEqual(preparations, 1, "Rejected tabs must not prepare a preview LUT either")
        clock.now = 200_000_000
        let owner = UUID()
        renderer.activate(owner: owner)
        let next = await renderer.render(owner: owner, source: buffer, effects: prepare)
        XCTAssertNotNil(next)
        XCTAssertEqual(invocations.value, 2)
        XCTAssertEqual(preparations, 2)
        XCTAssertFalse(renderer.isCurrent(try XCTUnwrap(first)))
    }

    func testSourceAndOptionChangesDiscardWorkAlreadyInsideTheRenderer() async throws {
        let clock = InspectorPreviewTestClock()
        let release = DispatchSemaphore(value: 0)
        let optionStarted = InspectorPreviewTestSignal("Option render started")
        let sourceStarted = InspectorPreviewTestSignal("Source render started")
        let invocations = InspectorRenderInvocationCounter()
        let reference = try Self.referenceImage()
        let renderer = MonitorInspectorImageRenderer(
            now: { clock.now },
            operation: { _, _ in
                if invocations.increment() == 1 {
                    optionStarted.signal()
                } else {
                    sourceStarted.signal()
                }
                XCTAssertEqual(
                    release.wait(timeout: .now() + 10), .success,
                    "Test did not release the work the renderer was already running")
                return reference
            }, workerQoS: inspectorTestWorkerQoS)
        let buffer = try Self.buffer(width: 8, height: 8)
        let owner = UUID()
        renderer.activate(owner: owner)
        let optionTask = Task {
            await renderer.render(owner: owner, source: buffer, effects: { LiveImageEffects() })
        }
        try await optionStarted.wait()
        renderer.invalidate(owner: owner)
        release.signal()
        let optionResult = await optionTask.value
        XCTAssertNil(optionResult, "Old option epochs must not publish")

        clock.now = 200_000_000
        let sourceTask = Task {
            await renderer.render(owner: owner, source: buffer, effects: { LiveImageEffects() })
        }
        try await sourceStarted.wait()
        renderer.invalidate(owner: owner)
        release.signal()
        let sourceResult = await sourceTask.value
        XCTAssertNil(sourceResult, "Old source epochs must not publish")
    }

    func testPlaybackPreviewWaitsForTheClipAndNeverFallsBackToCameraSource() throws {
        let bus = LiveFrameSampleBus(profile: ScopeExposureCeiling.sourceProfile)
        let camera = try Self.buffer(width: 8, height: 8)
        let clip = try Self.buffer(width: 16, height: 8)
        let live = bus.openSource(.live)
        bus.publish(live, source: camera, transfer: .rec709, reportedTransfer: .rec709, bundle: nil)
        let playback = bus.openSource(.playback)
        XCTAssertNil(bus.inspectorSource)
        bus.publish(playback, source: clip, transfer: .dlog2, bundle: nil)
        XCTAssertTrue(bus.inspectorSource?.buffer === clip)
        XCTAssertEqual(bus.inspectorSource?.transfer, .dlog2)
        bus.clearPlaybackSource(playback)
        XCTAssertNil(bus.inspectorSource)
        bus.closeSource(playback)
        XCTAssertTrue(bus.inspectorSource?.buffer === camera)
        bus.closeSource(live)
        XCTAssertNil(bus.inspectorSource)
    }

    private static func referenceImage() throws -> CGImage {
        try XCTUnwrap(
            CIContext().createCGImage(
                CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1)),
                from: CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    private static func buffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let source = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(source, [])
        if let address = CVPixelBufferGetBaseAddress(source) {
            memset(address, 200, CVPixelBufferGetBytesPerRow(source) * height)
        }
        CVPixelBufferUnlockBaseAddress(source, [])
        return source
    }
}

/// Deterministic monotonic time for both worker and real inspector mount tests.
final class InspectorPreviewTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: UInt64 = 0
    private var advancesUntilFrozen: Bool
    private var nextRead: InspectorPreviewTestSignal?

    init(advancesUntilFrozen: Bool = false) {
        self.advancesUntilFrozen = advancesUntilFrozen
    }

    /// Freeze at the clock value used for admission, not at delayed worker entry.
    func freezeAtLastRead() {
        lock.lock()
        advancesUntilFrozen = false
        lock.unlock()
    }

    func signalNextRead(_ signal: InspectorPreviewTestSignal) {
        lock.lock()
        nextRead = signal
        lock.unlock()
    }

    var now: UInt64 {
        get {
            lock.lock()
            defer { lock.unlock() }
            if advancesUntilFrozen { time = DispatchTime.now().uptimeNanoseconds }
            nextRead?.signal()
            nextRead = nil
            return time
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            time = newValue
        }
    }
}

/// The render closure runs on its worker queue while assertions run on main.
private final class InspectorRenderInvocationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

/// These tests block the renderer's worker and await its events from the main actor. Production
/// runs that worker at utility QoS; on a loaded hosted simulator utility work entered 6 s after
/// admission while the main thread ran within milliseconds (CI trace 2026-10-23), past the event
/// budget below. The worker therefore runs at the waiter's tier here; admission is unchanged.
let inspectorTestWorkerQoS: DispatchQoS = .userInitiated

/// Wait for the worker's event, not a presumed utility-queue scheduling delay.
/// The finite fallback throws out of the test before cancellation assertions
/// can manufacture a cascade; each caller releases blocked work in defer.
final class InspectorPreviewTestSignal: Sendable {
    static let timeoutSeconds = 10
    private let name: String
    private let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(_ name: String) {
        self.name = name
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pair.stream
        continuation = pair.continuation
    }

    func signal() {
        continuation.yield(())
        continuation.finish()
    }

    func wait(timeout: Duration = .seconds(timeoutSeconds)) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in self.events { return }
                    throw CancellationError()
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw WaitFailure(event: self.name)
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        } catch let failure as WaitFailure {
            // Only a timeout that won records an issue, and it does so before the caller's
            // defer runs. XCTest reports the last Swift error it observed in the test, and UIKit
            // teardown throws and swallows internal Gestures errors ("InvalidTransition").
            XCTFail(failure.description)
            throw failure
        }
    }

    private struct WaitFailure: Error, CustomStringConvertible {
        let event: String
        var description: String { "Inspector synchronization event did not arrive: \(event)" }
    }
}

/// The event wait's own failure report: recorded exactly when the wait fails.
/// Main actor: XCTExpectFailure scopes the test from the main thread.
@MainActor
final class InspectorPreviewTestSignalTests: XCTestCase {
    /// A missed event names itself even when the caller's UIKit teardown throws and swallows
    /// framework errors afterwards; XCTest would otherwise report the last of those instead.
    func testTimedOutSignalRecordsTheMissingEventItself() async {
        let recorded = InspectorSignalIssueCount()
        XCTExpectFailure("The timeout records its own issue", options: recorded.options())
        let signal = InspectorPreviewTestSignal("SIMULATED event that never arrives")
        var thrown = false
        do { try await signal.wait(timeout: .milliseconds(50)) } catch { thrown = true }
        XCTAssertTrue(thrown, "A missing event must throw")
        XCTAssertEqual(recorded.value, 1, "Exactly one issue names the missed event")
    }

    /// An event and its timeout finishing together: a wait that returns records nothing.
    func testIssueIsRecordedExactlyWhenTheWaitFails() async {
        let recorded = InspectorSignalIssueCount()
        let options = recorded.options()
        options.isStrict = false
        XCTExpectFailure("Only waits that fail record their timeout", options: options)
        var thrown = 0
        for index in 0..<200 {
            let signal = InspectorPreviewTestSignal("SIMULATED event \(index)")
            signal.signal()
            do { try await signal.wait(timeout: .zero) } catch { thrown += 1 }
        }
        XCTAssertEqual(recorded.value, thrown, "Only a wait that failed may record its timeout")
    }
}

/// Counts the timeout issues an expected-failure scope receives.
private final class InspectorSignalIssueCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func options() -> XCTExpectedFailure.Options {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { [self] issue in
            guard issue.compactDescription.contains("did not arrive: SIMULATED event") else {
                return false
            }
            lock.withLock { count += 1 }
            return true
        }
        return options
    }
}

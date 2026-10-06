import Foundation
import Insta360Apple
import Testing

@testable import OpenInstaViewCore

@Suite struct HeadTrackNativeTests {
    private let origin = GimbalWaypoint(yawDeg: -20, pitchDeg: -10, zoom: 1, nativePitchDeg: -171)

    /// OPTIONAL-02 gate for Luna: shared head tracking and waypoint capture run on the shell
    /// reach, which lies inside the reach Luna declares, so they never command Luna past it.
    @Test func shellReachLiesInsideTheDeclaredLunaReach() {
        #expect(HeadTrackNative().bounds == HeadTrack.Reach.bounds)
        #expect(LunaCameraSession.motion.bounds.contains(HeadTrack.Reach.bounds))
        #expect(LunaCameraSession.motion.bounds.tilt == -57...90)
        #expect(!LunaCameraSession.motion.axes.contains(.zoom), "Luna moves keep one zoom")
        var track = HeadTrackNative()
        #expect(track.center(pose: origin) == .centered)
        for look in stride(from: -400.0, through: 400, by: 37) {
            let target = track.target(lookRightDeg: look, lookUpDeg: look / 2)
            #expect(target.flatMap(LunaCameraSession.motion.target) != nil)
        }
    }

    @Test func capturedForwardMapsHeadAnglesWithoutRateCalibration() {
        var track = HeadTrackNative()
        #expect(track.center(pose: origin) == .centered)
        let forward = track.target(lookRightDeg: 0, lookUpDeg: 0)
        #expect(forward == origin)
        let point = track.target(lookRightDeg: 53, lookUpDeg: 12)
        #expect(point?.yawDeg == 33)
        #expect(point?.pitchDeg == 2)
        #expect(point?.nativePitchDeg == 177)
        #expect(HeadTrackNative.commandDuration == 0.1)
        // A 100 ms native horizon does not impose an artificial angular-speed cap.
        #expect((point?.yawDeg ?? 0) - origin.yawDeg > 50 * HeadTrackNative.commandDuration)
    }

    @Test func clampBodyLookBeforeMappingNativePitch() {
        var track = HeadTrackNative()
        var edgeOrigin = origin
        edgeOrigin.yawDeg = 200
        #expect(track.center(pose: edgeOrigin) == .centered)
        let point = track.target(lookRightDeg: 120, lookUpDeg: 100)
        #expect(point?.yawDeg == HeadTrack.Reach.panMaxDeg)
        #expect(point?.pitchDeg == HeadTrack.Reach.tiltMaxDeg)
        #expect(point?.nativePitchDeg == 109)
        let back = track.target(lookRightDeg: 0, lookUpDeg: 0)
        #expect(back == edgeOrigin)
    }

    @Test func hardTiltBoundsKeepObservationsHonestAndNativeEncodingSeparate() {
        var track = HeadTrackNative()
        #expect(track.center(pose: origin) == .centered)
        let lower = track.target(lookRightDeg: 0, lookUpDeg: -100)
        #expect(lower?.pitchDeg == -44)
        #expect(lower?.nativePitchDeg == -137)
        for pitch in [-44.1, 70.1] {
            let pose = GimbalWaypoint(yawDeg: 0, pitchDeg: pitch, zoom: 1, nativePitchDeg: -151)
            #expect(track.center(pose: pose) == .waitingForGimbal)
            var engine = GimbalMoveEngine(capabilities: MotionCapabilities(
                axes: [.pan, .tilt, .zoom], frame: .handle, bounds: HeadTrack.Reach.bounds,
                maxRateDegPerSec: nil, feedbackMaxAge: .milliseconds(300),
                arrivalToleranceDeg: 0.15))
            let started = engine.start(program: GimbalProgram(a: origin, b: pose), live: origin)
            #expect(!started)
        }
        #expect(HeadTrack.Reach.project(lookRight: 0, lookUp: 0, yaw0: 0, pitch0: -90).pitch == -44)
    }

    @Test func nativePitchCrossesWrapWithoutInventingMountOffset() {
        var track = HeadTrackNative()
        let mounted = GimbalWaypoint(yawDeg: 180, pitchDeg: 3, zoom: 1, nativePitchDeg: 179)
        #expect(track.center(pose: mounted) == .centered)
        #expect(track.target(lookRightDeg: 0, lookUpDeg: -2)?.nativePitchDeg == -179)
        #expect(track.target(lookRightDeg: 10, lookUpDeg: 0)?.yawDeg == 190)
    }

    @Test func lockRequiresCompleteNativePoseAndStillHead() {
        var track = HeadTrackNative()
        #expect(track.center(pose: nil) == .waitingForGimbal)
        #expect(track.center(pose: GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)) == .waitingForGimbal)
        #expect(track.center(pose: GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: .nan)) == .waitingForGimbal)
        #expect(track.center(pose: origin, gyroYaw: 0.1) == .waitingForStill)
        #expect(track.center(pose: origin, gyroLookUp: .nan) == .waitingForStill)
        #expect(!track.isCentered)
    }

    @Test func cachedSamplesExpireWithoutChangingPose() {
        #expect(HeadTrackNative.headSampleIsFresh(measuredAt: 10, now: 10.1))
        #expect(!HeadTrackNative.headSampleIsFresh(measuredAt: 10, now: 10.201))
        #expect(!HeadTrackNative.headSampleIsFresh(measuredAt: nil, now: 10.1))
        #expect(!HeadTrackNative.headSampleIsFresh(measuredAt: 11, now: 10))
        #expect(!HeadTrackNative.headSampleIsFresh(measuredAt: .nan, now: 10))
        #expect(!HeadTrackNative.headSampleIsFresh(measuredAt: 10, now: .infinity))
    }

    @Test func retargetIsImmediateAndInvalidLookCannotMove() {
        var track = HeadTrackNative()
        #expect(track.target(lookRightDeg: 20, lookUpDeg: 0) == nil)
        #expect(track.center(pose: origin) == .centered)
        #expect(track.target(lookRightDeg: 20, lookUpDeg: 0)?.yawDeg == 0)
        #expect(track.target(lookRightDeg: -20, lookUpDeg: 0)?.yawDeg == -40)
        #expect(track.target(lookRightDeg: .nan, lookUpDeg: 0) == nil)
        track.reset()
        #expect(!track.isCentered)
        #expect(track.lastTarget == nil)
        #expect(track.target(lookRightDeg: 20, lookUpDeg: 0) == nil)
    }

    @Test func queuedOldMeasurementsAndPriorGenerationCallbacksAreRejected() {
        var gate = HeadTrackNativeSampleGate()
        let first = gate.begin()
        // Callback is delivered now, but its source measurement is already old.
        #expect(!gate.accepts(first, measuredAt: 10, now: 10.3))
        #expect(gate.accepts(first, measuredAt: 10.25, now: 10.3))
        gate.invalidate()
        #expect(!gate.accepts(first, measuredAt: 10.3, now: 10.3))
        let second = gate.begin()
        #expect(!gate.isCurrent(first))
        #expect(!gate.accepts(first, measuredAt: 10.4, now: 10.4))
        #expect(gate.accepts(second, measuredAt: 10.4, now: 10.4))
    }
}

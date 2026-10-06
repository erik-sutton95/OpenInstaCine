import Foundation
import Testing

@testable import OpenInstaViewCore

@Suite struct GimbalProgramTests {
    private let a = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
    private let b = GimbalWaypoint(yawDeg: 30, pitchDeg: 10, zoom: 3)

    @Test func engineRefusesPartialProgram() {
        var engine = GimbalMoveEngine(capabilities: MotionCapabilities(
            axes: [.pan, .tilt, .zoom], frame: .handle, bounds: HeadTrack.Reach.bounds,
            maxRateDegPerSec: nil, feedbackMaxAge: .milliseconds(300), arrivalToleranceDeg: 0.15))
        let started = engine.start(program: GimbalProgram(a: a), live: a)
        #expect(!started)
    }

    /// Raw yaw past the gap middle unwraps onto the long side; measured
    /// angles elsewhere pass through, with no invented stops.
    @Test(arguments: [
        (-150.0, 210.0), (50, 50), (90, 90), (100, 100), (-48, -48),
        (-135, 225), (-180, 180), (180, 180), (-80, -80), (-100, 260),
    ])
    func unwrapYawCrossesTheRawWrapOnThePositiveArc(raw: Double, expected: Double) {
        #expect(GimbalWaypoint.unwrapYaw(raw) == expected)
    }

    @Test func lerpFromShortSideToSelfieNeverEntersTheGap() {
        let from = GimbalWaypoint(yawDeg: 50, pitchDeg: 0, zoom: 1)
        let to = GimbalWaypoint(yawDeg: 200, pitchDeg: 0, zoom: 1)
        for i in 0...80 {
            let yaw = GimbalMoveEngine.lerp(from, to, u: Double(i) / 80).yawDeg
            #expect(yaw <= HeadTrack.Reach.panMaxDeg + 1e-9)
            #expect(yaw >= HeadTrack.Reach.panMinDeg - 1e-9)
        }
    }

    @Test func durationStepsByHalfSecond() {
        #expect(GimbalProgram.steppedDuration(1.5, delta: 0.5, floor: 1.0) == 2.0)
        #expect(GimbalProgram.durationLabel(1.5) == "1.5s")
    }

    @Test func nanoHasNoGimbal() {
        #expect(CameraModel(name: "Osmo Pocket 4 Pro").hasGimbal)
        #expect(!CameraModel(name: "Osmo Nano").hasGimbal)
    }

}

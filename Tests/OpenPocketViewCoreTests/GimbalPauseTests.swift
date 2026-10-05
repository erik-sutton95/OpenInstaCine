import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalPauseTests {
    private func point(_ yaw: Double, _ pitch: Double = 0) -> GimbalWaypoint {
        GimbalWaypoint(yawDeg: yaw, pitchDeg: pitch, zoom: 1, nativePitchDeg: -pitch)
    }

    private func ready(_ program: GimbalProgram) -> GimbalMoveEngine {
        var engine = GimbalMoveEngine()
        let operation1 = engine.start(program: program, live: program.a!)
        #expect(operation1)
        for _ in 0..<200 { _ = engine.tick(dt: 0.01, live: program.a!) }
        return engine
    }

    @Test func curveCutsPreserveFutureGeometryAndAbsorbCoast() {
        let program = GimbalProgram(a: point(0), b: point(30), c: point(30, 20),
            durationAB: 3, durationBC: 2, smoothness: 1)
        let original = GimbalProgramCurve(program: program)!
        for cut in [1.0, 2.5, 4.5] {
            let actual = point(12, 3)
            let rest = original.remaining(after: cut, from: actual)
            #expect(rest.position(at: 0) == actual)
            #expect(abs(rest.duration - (5 - cut)) < 1e-9)
            #expect(rest.position(at: rest.duration) == program.c)
            #expect(rest.samples().allSatisfy { $0 == $0.clamped() })
            if cut < 4 {
                #expect(rest.position(at: 4 - cut) == original.position(at: 4))
            }
            let again = rest.remaining(after: 0.1, from: point(13, 3))
            #expect(again.position(at: 0) == point(13, 3))
            #expect(abs(again.duration - (rest.duration - 0.1)) < 1e-9)
            #expect(again.position(at: again.duration) == program.c)
        }
        let exactCut = original.remaining(after: 2.5, from: original.position(at: 2.5))
        #expect(GimbalMoveEngine.angularDistance(exactCut.position(at: 0.4), original.position(at: 2.9)) < 1e-9)
    }

}

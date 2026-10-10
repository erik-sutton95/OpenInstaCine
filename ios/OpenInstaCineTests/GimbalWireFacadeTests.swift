import Insta360Apple
import Insta360Protocol
import OpenCineMotion
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// Characterization of the gimbal requests the session facade sends: the held stick's MOVE
/// stream, release, recenter, flip, SET_ANGLE and GET_ANGLE, observed on a live Luna session.
@MainActor
final class GimbalWireFacadeTests: XCTestCase {
    private final class Wire {
        var sent: [(request: LunaRequest, timeout: Duration?, at: TimeInterval)] = []
        var reply: (LunaRequest) -> Data = { _ in Data() }
        func requests(_ command: LunaRequest) -> [LunaRequest] {
            sent.map(\.request).filter { $0 == command }
        }
    }

    private func liveSession(_ wire: Wire) -> CameraSession {
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        let luna = LunaCameraSession(
            send: { request in
                wire.sent.append((request, nil, ProcessInfo.processInfo.systemUptime))
                return wire.reply(request)
            },
            sendWithin: { request, timeout in
                wire.sent.append((request, timeout, ProcessInfo.processInfo.systemUptime))
                return wire.reply(request)
            },
            functionMode: { LunaFunctionMode.normalVideo.rawValue },
            readSettings: {}, readCapture: {})
        luna.linkChanged(.streaming, serial: "LUNA-TEST")
        session.lunaSessionOverride = luna
        session.phase = .live
        return session
    }

    private func waitUntil(_ predicate: () -> Bool, timeout: Double = 5) async -> Bool {
        let end = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < end {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    func testHeldStickStreamsMoveEvery50msZerosIncludedAndRestSendsOneRelease() async throws {
        let wire = Wire()
        let session = liveSession(wire)
        // Ease-in: 0.5 → 0.25 of full scale (24.75 → 25), −1 → −99.
        session.updateGimbalStick(x: 0.5, y: -1)
        let pushed = try LunaProtocol.gimbalMove(upDown: -99, leftRight: 25)
        let streamed = await waitUntil { wire.requests(pushed).count >= 3 }
        XCTAssertTrue(streamed)
        let times = wire.sent.filter { $0.request == pushed }.map(\.at)
        for (earlier, later) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 0.045, "never faster than one MOVE per 50 ms")
        }
        XCTAssertTrue(wire.sent.filter { $0.request == pushed }.allSatisfy { $0.timeout == .seconds(2) })

        // MOVE 0, 0 and the release are the same bytes; the stream carries a 2 s timeout, the
        // release the backend default.
        session.updateGimbalStick(x: 0.05, y: 0)
        let rest = try LunaProtocol.gimbalMove(upDown: 0, leftRight: 0)
        XCTAssertEqual(rest, try LunaProtocol.gimbalReleaseRequest())
        let streamedRest = { wire.sent.filter { $0.request == rest && $0.timeout == .seconds(2) }.count }
        let releases = { wire.sent.filter { $0.request == rest && $0.timeout == nil }.count }
        let still = await waitUntil { streamedRest() >= 2 }
        XCTAssertTrue(still, "a held stick inside the deadzone keeps streaming MOVE 0, 0")
        XCTAssertEqual(releases(), 0)

        session.endGimbalStick()
        let released = await waitUntil { releases() == 1 }
        XCTAssertTrue(released)
        let count = wire.sent.count
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(wire.sent.count, count, "the stream ends at rest")
    }

    func testRecenterAndFlipSendTheirGimbalActions() async throws {
        let wire = Wire()
        let session = liveSession(wire)
        session.recenterGimbal()
        XCTAssertEqual(session.controlNote, "Gimbal re-centered")
        let recenter = try LunaProtocol.gimbalRecenterRequest()
        let recentered = await waitUntil { wire.requests(recenter).count == 1 }
        XCTAssertTrue(recentered)
        session.flipGimbal()
        let flip = try LunaProtocol.gimbalFlipRequest()
        let flipped = await waitUntil { wire.requests(flip).count == 1 }
        XCTAssertTrue(flipped)
    }

    func testSetAngleWrapsYawAndClampsPitchToTheDeclaredReach() async throws {
        let wire = Wire()
        let session = liveSession(wire)
        session.sendGimbalAngle(GimbalWaypoint(yawDeg: 270, pitchDeg: 120, zoom: 1))
        let top = Float(LunaCameraSession.motion.bounds.tilt.upperBound)
        let aim = try LunaProtocol.gimbalSetAngle(pitch: top, yaw: -90)
        let sent = await waitUntil { wire.requests(aim).count == 1 }
        XCTAssertTrue(sent)
        XCTAssertEqual(wire.sent.last?.timeout, .seconds(2))
    }

    func testAngleReadParsesAndKeepsTheReading() async throws {
        let wire = Wire()
        let session = liveSession(wire)
        let read = try LunaProtocol.gimbalGetAngleRequest()
        wire.reply = { request in
            guard request == read,
                let pitch = try? ProtoMessage.float(field: 3, value: -12.5),
                let yaw = try? ProtoMessage.float(field: 4, value: 33)
            else { return Data() }
            return pitch + yaw
        }
        let angle = await session.readGimbalAngle()
        XCTAssertEqual(angle, LunaGimbalAngle(pitch: -12.5, yaw: 33))
        XCTAssertEqual(session.gimbalAngle?.angle, angle)
        XCTAssertEqual(wire.sent.last?.request, read)
        XCTAssertEqual(wire.sent.last?.timeout, .seconds(1))
    }

    func testNoLinkSendsNoGimbalRequest() async throws {
        let wire = Wire()
        let session = liveSession(wire)
        session.lunaSessionOverride?.close(.linkLost)
        session.updateGimbalStick(x: 1, y: 0)
        session.recenterGimbal()
        session.flipGimbal()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(wire.sent.isEmpty)
        XCTAssertFalse(session.gimbalStick.isHeld)
    }
}

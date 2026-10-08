import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineMotion
import XCTest

@testable import OpenInstaCine

/// The actual app's source adapter, using live LunaCameraSession fixtures and exact wire requests.
@MainActor final class ProgrammedMoveSourceTests: XCTestCase {
    private final class Wire {
        var sent: [LunaRequest] = []
        @MainActor func session() -> LunaCameraSession {
            let session = LunaCameraSession(send: { [self] request in sent.append(request); return Data() },
                functionMode: { LunaFunctionMode.normalVideo.rawValue }, readSettings: {}, readCapture: {})
            session.linkChanged(.streaming, serial: "LUNA-PROGRAM-TEST")
            return session
        }
    }

    private func facade(_ source: LunaCameraSession) -> CameraSession {
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        session.lunaSessionOverride = source
        session.phase = .live
        return session
    }

    func testCapturedSourceNeverLooksUpAReplacementCamera() async throws {
        let firstWire = Wire(); let first = firstWire.session(); let facade = self.facade(first)
        let source = try XCTUnwrap(facade.programmedMoveSource())
        XCTAssertTrue(source.isCurrent())
        let secondWire = Wire(); let second = secondWire.session()
        facade.lunaSessionOverride = second
        XCTAssertFalse(source.isCurrent())
        let target = try XCTUnwrap(source.motion.capabilities.target(.init(yawDeg: 190, pitchDeg: 5, zoom: 1)))
        // Even a direct call cannot bypass the captured source's identity/epoch admission.
        let accepted = await source.motion.move(to: target, over: nil)
        XCTAssertFalse(accepted)
        XCTAssertTrue(firstWire.sent.isEmpty)
        XCTAssertTrue(secondWire.sent.isEmpty)
        let next = try XCTUnwrap(facade.programmedMoveSource())
        let nextAccepted = await next.motion.move(to: target, over: nil)
        XCTAssertTrue(nextAccepted)
        XCTAssertEqual(secondWire.sent, [try LunaProtocol.gimbalSetAngle(pitch: 5, yaw: -170)])
        facade.cancelProgrammedMove()
    }

    func testSameSessionReentryRetiresTheCapturedEpoch() async throws {
        let wire = Wire(); let session = wire.session(); let facade = self.facade(session)
        let source = try XCTUnwrap(facade.programmedMoveSource())
        let target = try XCTUnwrap(source.motion.capabilities.target(.init(yawDeg: 10, pitchDeg: 5, zoom: 1)))
        session.linkChanged(.idle, serial: nil)
        session.linkChanged(.streaming, serial: "LUNA-PROGRAM-TEST")
        XCTAssertFalse(source.isCurrent())
        let oldAccepted = await source.motion.move(to: target, over: nil)
        XCTAssertFalse(oldAccepted)
        XCTAssertTrue(wire.sent.isEmpty)
        let next = try XCTUnwrap(facade.programmedMoveSource())
        XCTAssertTrue(next.isCurrent())
        let nextAccepted = await next.motion.move(to: target, over: nil)
        XCTAssertTrue(nextAccepted)
        XCTAssertEqual(wire.sent, [try LunaProtocol.gimbalSetAngle(pitch: 5, yaw: 10)])
        facade.cancelProgrammedMove()
    }

    func testGenerationAndBackgroundRetireWithoutAutomaticallyStarting() throws {
        let wire = Wire(); let session = wire.session(); let facade = self.facade(session)
        let source = try XCTUnwrap(facade.programmedMoveSource())
        facade.connectGeneration += 1
        XCTAssertFalse(source.isCurrent())
        let next = try XCTUnwrap(facade.programmedMoveSource())
        facade.noteSceneBecameInactive()
        XCTAssertFalse(next.isCurrent())
        facade.phase = .idle
        facade.noteSceneBecameActive()
        XCTAssertFalse(facade.gimbalMoveRunning)
        XCTAssertTrue(wire.sent.isEmpty)
    }
}

import Insta360Apple
import Insta360Protocol
import OpenCineHostedTestSupport
import XCTest

@testable import OpenInstaCine

/// Characterization of the session facade's keyframe request (IFRAME_REQUEST, cmd 105).
@MainActor
final class LunaKeyframeFacadeTests: XCTestCase {
    func testKeyframeRequestIsEmptyRateLimitedAndNeedsALiveLink() async throws {
        var sent: [(request: LunaRequest, timeout: Duration?)] = []
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        let luna = LunaCameraSession(
            send: {
                sent.append(($0, nil))
                return Data()
            },
            sendWithin: {
                sent.append(($0, $1))
                return Data()
            },
            functionMode: { LunaFunctionMode.normalVideo.rawValue },
            readSettings: {}, readCapture: {})
        luna.linkChanged(.streaming, serial: "LUNA-TEST")
        session.lunaSessionOverride = luna
        session.phase = .live

        session.requestKeyframe(reason: "test")
        session.requestKeyframe(reason: "test")
        // The request is sent from a task; wait for it, then hold a negative window for a second.
        _ = await HostedCondition.wait { !sent.isEmpty }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.count, 1, "at most one request a second")
        XCTAssertEqual(sent.first?.request.wireCode, 105)
        XCTAssertEqual(sent.first?.request.body, Data())
        XCTAssertNil(sent.first?.timeout)

        // Past the product's one-second limit (a lower bound; it reads Date() directly).
        try await Task.sleep(for: .milliseconds(1000))
        session.requestKeyframe(reason: "test")
        _ = await HostedCondition.wait { sent.count == 2 }
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.last?.request, sent.first?.request)

        luna.close(.linkLost)
        try await Task.sleep(for: .milliseconds(1000))
        session.requestKeyframe(reason: "test")
        // Negative window: nothing may be sent without a control link.
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.count, 2, "no request without a control link")
    }
}

import Insta360Apple
import Insta360Protocol
import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

/// Characterization of the session facade's camera clock: the clock sync it sends when the link
/// goes live, and the time-of-day timecode it derives from live frame stamps.
@MainActor
final class LunaClockFacadeTests: XCTestCase {
    private final class Wire {
        var sent: [(request: LunaRequest, timeout: Duration?)] = []
        var refuses: (LunaRequest) -> Bool = { _ in false }
        func reply(_ request: LunaRequest, _ timeout: Duration?) throws -> Data {
            sent.append((request, timeout))
            if refuses(request) { throw CancellationError() }
            return Data()
        }
    }

    private func liveSession(_ wire: Wire) -> CameraSession {
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
        let luna = LunaCameraSession(
            send: { try wire.reply($0, nil) }, sendWithin: { try wire.reply($0, $1) },
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

    func testClockSyncSetsTheClockThenSyncsToTheMillisecondTwice() async throws {
        let wire = Wire()
        let session = liveSession(wire)
        let zone = TimeZone.current
        let before = Date()
        session.syncCameraClock()
        let synced = await waitUntil { wire.sent.count == 3 }
        let after = Date()
        XCTAssertTrue(synced)
        let seconds = UInt64(before.timeIntervalSince1970)...UInt64(after.timeIntervalSince1970)
        XCTAssertTrue(
            seconds.contains { second in
                wire.sent.first?.request
                    == (try? LunaProtocol.setClockRequest(
                        unixSeconds: second, timeZoneSeconds: Int32(zone.secondsFromGMT(for: before)),
                        zone: zone.identifier))
            }, "local time, offset and zone name first")
        let milliseconds =
            UInt64((before.timeIntervalSince1970 * 1000).rounded(.down))...UInt64(
                (after.timeIntervalSince1970 * 1000).rounded(.up))
        for (count, sent) in wire.sent.dropFirst().enumerated() {
            XCTAssertTrue(
                milliseconds.contains {
                    sent.request == (try? LunaProtocol.syncTimeAccurateRequest(unixMilliseconds: $0, count: UInt32(count)))
                }, "cmd 214 count \(count), stamped at send")
        }
        XCTAssertEqual(wire.sent.map(\.timeout), [.seconds(2), .seconds(2), .seconds(2)])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(wire.sent.count, 3)
    }

    func testRefusedClockSendsNoMillisecondSync() async throws {
        let wire = Wire()
        wire.refuses = { $0.wireCode != LunaProtocol.syncTimeAccurateCode }
        let session = liveSession(wire)
        session.syncCameraClock()
        let tried = await waitUntil { wire.sent.count == 1 }
        XCTAssertTrue(tried)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(wire.sent.count, 1)
        XCTAssertNotEqual(wire.sent.first?.request.wireCode, LunaProtocol.syncTimeAccurateCode)
    }

    func testFrameTimecodePinsTheEarliestArrivalAndChangesOncePerSecond() throws {
        let session = liveSession(Wire())
        let zoneSeconds = TimeZone.current.secondsFromGMT()
        func expected(_ milliseconds: UInt64, _ offset: Double) -> String {
            LunaShellMapping.timecode(
                unixSeconds: Double(milliseconds) / 1000 + offset, timeZoneSeconds: zoneSeconds,
                fps: session.status.fps)
        }
        let first: UInt64 = 100_000
        let before = Date().timeIntervalSince1970
        session.noteFrameClock(first)
        let after = Date().timeIntervalSince1970
        let offset = try XCTUnwrap(session.frameClockOffset)
        // Pinned to the phone clock at arrival, less 90 ms of capture latency.
        XCTAssertGreaterThanOrEqual(offset, before - 100.09 - 1e-6)
        XCTAssertLessThanOrEqual(offset, after - 100.09 + 1e-6)
        XCTAssertEqual(session.status.timecode, expected(first, offset))

        // Older stamps arrive later than the pinned one: the offset holds, and the timecode
        // changes only when its second does.
        let wall = Double(first) / 1000 + offset
        let fraction = UInt64(((wall - wall.rounded(.down)) * 1000).rounded(.up))
        let sameSecond: (UInt64, UInt64)
        if fraction >= 300 {
            sameSecond = (first, first - 250)
        } else {
            let previous = first - fraction - 500
            session.noteFrameClock(previous)
            XCTAssertEqual(session.status.timecode, expected(previous, offset))
            sameSecond = (previous, previous - 250)
        }
        session.noteFrameClock(sameSecond.1)
        XCTAssertEqual(session.status.timecode, expected(sameSecond.0, offset), "once a second")
        if fraction >= 300 {
            let previous = first - fraction - 300
            session.noteFrameClock(previous)
            XCTAssertEqual(session.status.timecode, expected(previous, offset))
        }
        XCTAssertEqual(session.frameClockOffset, offset)

        // A stamp ahead of its arrival re-pins earlier.
        session.noteFrameClock(first + 5_000)
        let repinned = try XCTUnwrap(session.frameClockOffset)
        XCTAssertGreaterThanOrEqual(repinned, offset - 5 - 1e-6)
        XCTAssertLessThan(repinned, offset - 4)

        // A clock sync starts the pinning over.
        session.syncCameraClock()
        XCTAssertNil(session.frameClockOffset)
    }
}

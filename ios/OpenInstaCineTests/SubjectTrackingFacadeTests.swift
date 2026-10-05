import Insta360Protocol
import OpenPocketViewCore
import XCTest

@testable import OpenInstaCine

/// Characterization of Deep Track and tap focus on the session facade, without a control link,
/// driven only through its public inputs. The wire side (cmd 237, cancel, tap ROI) and a pending
/// search before any lock are pinned with the Luna owner in OpenCine.
@MainActor
final class SubjectTrackingFacadeTests: XCTestCase {
    private func session() -> CameraSession {
        CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder())
    }

    /// Media 0x85 with the box at `x`, 0.15 × 0.27 (y omitted, as proto3 drops a zero float).
    private func frame(state: UInt8, x: Float) throws -> LunaTrackFrame {
        var box = Data([0x0d]) + withUnsafeBytes(of: x.bitPattern.littleEndian) { Data($0) }
        box += Data([0x1d]) + withUnsafeBytes(of: Float(0.15).bitPattern.littleEndian) { Data($0) }
        box += Data([0x25]) + withUnsafeBytes(of: Float(0.27).bitPattern.littleEndian) { Data($0) }
        return try LunaTrackFrame(Data([0x10, state, 0x22, UInt8(box.count)]) + box)
    }

    func testTrackingNotificationPromotesTheLostBoxAndEndsAfterALock() throws {
        let session = session()
        session.applyTrackingState(0)
        XCTAssertFalse(session.isTrackingActive, "a cancel with nothing tracked changes nothing")
        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        session.applyTrackFrame(try frame(state: 3, x: 0.42))
        let lost = try XCTUnwrap(session.searchBox)
        session.applyTrackingState(1)
        XCTAssertTrue(session.isTracking)
        XCTAssertNil(session.searchBox)
        XCTAssertEqual(session.subjectBox, TrackingBox.subject(from: lost))
        session.applyTrackingState(0)
        XCTAssertFalse(session.isTrackingActive, "a cancel after a lock clears everything")

        session.applyTrackingState(2)
        XCTAssertTrue(session.isTracking, "a lock without a search box still counts")
        XCTAssertNil(session.subjectBox)
        session.applyTrackingState(4)
        XCTAssertFalse(session.isTrackingActive)
    }

    func testTrackingFrameClearsTheFaceBox() throws {
        let session = session()
        session.faceBox = TrackingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        session.applyTrackFrame(try frame(state: 5, x: 0.4))
        XCTAssertNotNil(session.faceBox, "an idle frame before a lock leaves the face box")
        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        XCTAssertNil(session.faceBox)
    }

    func testTapFocusWithoutALinkMovesThePointLocallyAndCancelsTracking() throws {
        let session = session()
        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        session.faceBox = TrackingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        session.markFocus(at: CGPoint(x: 1.4, y: -0.2))
        XCTAssertFalse(session.isTrackingActive)
        XCTAssertNil(session.faceBox)
        XCTAssertEqual(session.focusPoint, CGPoint(x: 1, y: 0))
        XCTAssertNotNil(session.lastTapFocusAt)
        XCTAssertEqual(session.controlNote, "Connect the camera to use its controls.")
    }

    func testStartTrackingWithoutALinkChangesNothingAndATinyBoxIsRefused() throws {
        let session = session()
        session.startTracking(TrackingBox(x: 0.3, y: 0.2, width: 0.2, height: 0.4))
        XCTAssertFalse(session.isTrackingActive)
        XCTAssertEqual(session.controlNote, "Connect the camera to use its controls.")

        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        session.startTracking(TrackingBox(x: 0.5, y: 0.5, width: 0.05, height: 0.3))
        XCTAssertFalse(session.isTrackingActive, "too small clears the boxes before any link check")
        XCTAssertEqual(session.controlNote, "Frame Too Small")
    }

    func testCancelWithoutControlAndDisconnectClearTrackingLocally() throws {
        let session = session()
        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        session.cancelSubjectTracking()
        XCTAssertFalse(session.isTrackingActive)

        session.applyTrackFrame(try frame(state: 2, x: 0.4))
        session.applyTrackFrame(try frame(state: 3, x: 0.42))
        XCTAssertNotNil(session.searchBox)
        session.disconnect()
        XCTAssertFalse(session.isTrackingActive)
    }
}

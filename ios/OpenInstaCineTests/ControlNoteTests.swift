import OpenCineAppKit
import OpenCineCore
import XCTest

@testable import OpenInstaCine

/// Insta main's write copy (`sendControl`): a failed request said "X was not applied by the
/// camera."; a write the camera took but did not show reverted silently.
@MainActor
final class ControlNoteTests: XCTestCase {
    func testWritesKeepMainsNotes() {
        let notApplied = "ISO 800 was not applied by the camera."
        func note(_ stage: CommandStage, _ label: String = "ISO 800") -> String? {
            CameraSession.controlNote(for: stage, label)
        }
        XCTAssertNil(note(.confirmed))
        XCTAssertNil(note(.failed(.notApplied)))
        XCTAssertNil(note(.timedOut))
        XCTAssertNil(note(.failed(.superseded)))
        XCTAssertEqual(note(.rejected(.cameraRefused)), notApplied)
        XCTAssertEqual(note(.outcomeUnknown), notApplied)
        XCTAssertEqual(note(.failed(.notSent)), notApplied)
        XCTAssertEqual(note(.outcomeUnknown, "Stop"), "Stop was not applied by the camera.")
        XCTAssertEqual(note(.rejected(.notConnected)), MonitorControlModel.connectFirst)
        XCTAssertEqual(
            note(.rejected(.staleEpoch)), "ISO 800 was not sent: the camera state changed. Try again.")
    }
}

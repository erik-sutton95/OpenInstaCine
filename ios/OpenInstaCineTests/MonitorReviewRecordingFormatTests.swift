import OpenCineCore
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

#if targetEnvironment(simulator)
    /// SIMULATED review reports carry the recording format (resolution, frame rate and colour)
    /// through the session's own option decoding, so the review header shows it like the other apps.
    @MainActor final class MonitorReviewRecordingFormatTests: XCTestCase {
        func testReviewReportsTheStagedRecordingFormatAndColour() throws {
            var status = CameraStatus()
            status.iso = 400
            status.shutterDenom = 50
            status.whiteBalanceKelvin = 5600
            status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
            status.colorMode = .iLog
            let session = MonitorUIReview.simulatedSession(status: status)
            defer { session.close(.requested) }
            let format = session.current.recordingFormat
            XCTAssertEqual(format.dimensions.value?.width, 3840)
            XCTAssertEqual(format.dimensions.value?.height, 2160)
            XCTAssertEqual(
                session.current.settings[.frameRate]?.value, .frameRate(try XCTUnwrap(Rational.frameRate(25))))
            XCTAssertEqual(format.profile.value, "I-Log")
        }

        func testReviewWithoutAStagedFormatReportsNoneRatherThanInventingOne() {
            var status = CameraStatus()
            status.iso = 400
            status.shutterDenom = 50
            status.whiteBalanceKelvin = 5600
            let session = MonitorUIReview.simulatedSession(status: status)
            defer { session.close(.requested) }
            XCTAssertNil(session.current.recordingFormat.dimensions.value)
            XCTAssertNil(session.current.recordingFormat.profile.value)
        }
    }
#endif

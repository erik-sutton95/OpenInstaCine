import Foundation
import OpenInstaViewCore
import XCTest

@testable import OpenInstaCine

/// SIMULATED actual backend event consumer and snapshot builder; no connect, native decode or upload.
@MainActor
final class FeedIncidentProducerTests: XCTestCase {
  func testDuplicateAndReversedSnapshotClockCannotDiscardActualAUCount() {
        let model = AppModel()
        let session = model.session
    let baseline = session.feedIncidentSnapshot(now: 100)
    XCTAssertNil(baseline.rates.observed?.accessUnitHz)
    session.backend.eventHandler?(.videoAccessUnit(Data(), timestampMilliseconds: 1))
    XCTAssertNil(session.feedIncidentSnapshot(now: 100).rates.observed?.accessUnitHz)
    XCTAssertNil(session.feedIncidentSnapshot(now: 99).rates.observed?.accessUnitHz)
    let next = session.feedIncidentSnapshot(now: 101)
    XCTAssertEqual(next.rates.observed?.accessUnitHz, 1)
    XCTAssertNil(next.rates.observed?.packetHz)
    XCTAssertNil(next.rates.observed?.ackHz)
  }
  func testAUArrivalIsMeasuredWithoutFabricatingPacketsNativeAdmissionOrPresentation() {
        let model = AppModel()
        let session = model.session
        let before = session.feedIncidentSnapshot(now: 100)
        XCTAssertNil(before.ages.packetAge)
        XCTAssertNil(before.ages.accessUnitAge)
        XCTAssertNil(before.ages.presentAge)
        XCTAssertNil(before.ingress)
        session.backend.eventHandler?(.videoAccessUnit(Data(), timestampMilliseconds: 1))
        let after = session.feedIncidentSnapshot(now: 101)
        XCTAssertEqual(after.rates.accessUnitHz, 1)
        XCTAssertNotNil(after.ages.accessUnitAge)
        XCTAssertNil(after.ages.packetAge)
        XCTAssertNil(after.ages.statusAge)
        XCTAssertNil(after.ages.decodeAcceptAge)
        XCTAssertNil(after.ages.decodedOutputAge)
        XCTAssertNil(after.ages.presentAge)
        XCTAssertNil(after.ingress)
        XCTAssertFalse(after.lifecycle.liveEstablished)
        XCTAssertEqual(after.decoder.generation, session.decoder.sourceFrameGeneration)
    }

    func testConsumerRetirementClearsAUHistoryAndCoverageUsesActualHostState() {
        let model = AppModel()
        let session = model.session
        session.backend.eventHandler?(.videoAccessUnit(Data(), timestampMilliseconds: 1))
        XCTAssertNotNil(session.feedIncidentSnapshot().ages.accessUnitAge)
        session.incidentSettingsCovered = true
        let covered = session.feedIncidentSnapshot()
        XCTAssertTrue(covered.lifecycle.settingsCovered)
        XCTAssertFalse(covered.lifecycle.presentationExpected)
        session.disconnect()
        let retired = session.feedIncidentSnapshot()
        XCTAssertNil(retired.ages.accessUnitAge)
        XCTAssertFalse(retired.lifecycle.connected)
        XCTAssertNil(retired.ages.decodedOutputAge)
        XCTAssertNil(retired.ages.presentAge)
    }
}

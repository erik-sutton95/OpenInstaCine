import Insta360Apple
import Insta360Protocol
import OpenCineAppKit
import OpenCineCore
import XCTest

@testable import OpenInstaCine

/// The app's Multiview host: four Luna tiles on OpenCine's shared stage, its journal store, the
/// capability values the shared screen reads and the Auto LUT conversion. Hardware-untested: no
/// camera is reached here.
@MainActor
final class MultiviewSessionTests: XCTestCase {
    private func session(journal: MultiviewJournalStorage = MultiviewJournalStorage(load: { nil }, save: { _ in true }))
        -> MultiviewSession
    {
        MultiviewSession(
            makeBackend: { AppModel.makeBackend() },
            discover: { AsyncStream { $0.finish() } },
            journal: journal)
    }

    private func camera(_ slot: Int, lut: Bool = false) -> MultiviewStageJournal.Camera {
        MultiviewStageJournal.Camera(
            slot: slot, id: UUID(), name: "Luna \(slot)", identity: Array("LUNA-\(slot)".utf8),
            address: "192.168.1.3\(slot)", experimental: false, lutEnabled: lut)
    }

    func testTheStageHasFourLunaTilesWithTheirOwnConnections() {
        let stage = session()
        XCTAssertEqual(stage.tiles.count, 4)
        XCTAssertEqual(Set(stage.tiles.map { ObjectIdentifier($0.backend) }).count, 4)
        XCTAssertTrue(stage.tiles.allSatisfy { $0.session.multiviewMember })
        XCTAssertTrue(stage.coordinator.host === stage)
    }

    func testTheHostOffersSettingsAutoLUTAndTheRecordPreference() {
        let stage = session()
        XCTAssertTrue(stage.editsCameraSettings)
        XCTAssertTrue(stage.appliesAutoLUT)
        // Without the app model, the confirmation stays on (the safe default).
        XCTAssertTrue(stage.confirmsRecord)
        XCTAssertNil(stage.readings(slot: 0))
        XCTAssertNil(stage.cameraSettings(slot: 0))
        XCTAssertFalse(stage.openLiveView(slot: 0))
    }

    func testNoTileSearchesAHostAnotherTileHolds() {
        let stage = session()
        stage.tiles[1].member.controlHost = "192.168.1.31"
        stage.tiles[2].member.controlHost = "192.168.1.32"
        XCTAssertEqual(stage.tiles[1].backend.stationHostsInUse?(), ["192.168.1.32"])
        XCTAssertEqual(stage.tiles[0].backend.stationHostsInUse?(), ["192.168.1.31", "192.168.1.32"])
    }

    func testOnlyILogGetsTheBundledConversion() {
        XCTAssertEqual(MultiviewSession.conversion(LunaColorMode.iLog.label), "I-Log to Rec.709")
        XCTAssertNil(MultiviewSession.conversion(LunaColorMode.standard.label))
        XCTAssertNil(MultiviewSession.conversion(LunaColorMode.dolbyVision.label))
    }

    func testTheStageStoreKeepsOnlyStagesThisAppCanRestore() throws {
        let stage = MultiviewStageJournal.Stage(
            ssid: "Studio", hotspot: false, layout: "Grid", focusedIndex: 2,
            cameras: [camera(0, lut: true)], pendingReset: [camera(1)], fill: true)
        let data = try XCTUnwrap(MultiviewStageStore.encode(stage))
        XCTAssertEqual(MultiviewStageStore.decode(data), stage)

        var unfocusable = stage
        unfocusable.focusedIndex = 4
        XCTAssertNil(MultiviewStageStore.encode(unfocusable))
        var five = stage
        five.cameras = (0..<5).map { camera($0 % 4) }
        XCTAssertNil(MultiviewStageStore.encode(five))
        XCTAssertNil(MultiviewStageStore.decode(try JSONEncoder().encode(five)))
        XCTAssertNil(MultiviewStageStore.decode(Data("not json".utf8)))
    }
}

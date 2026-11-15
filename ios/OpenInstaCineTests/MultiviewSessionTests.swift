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

    func testAutoLUTFollowsWhatThePreviewCarries() {
        // Live View's rule: an I-Log recording previews graded unless the operator says Color
        // Recovery is off (the flat I-Log preview); only a flat preview gets the conversion.
        XCTAssertEqual(MultiviewSession.previewProfile(LunaColorMode.iLog.label, flat: true), "I-Log")
        XCTAssertEqual(MultiviewSession.previewProfile(LunaColorMode.iLog.label, flat: false), "Standard")
        XCTAssertEqual(MultiviewSession.previewProfile("Dolby Vision", flat: false), "Dolby Vision")
        XCTAssertNil(MultiviewSession.conversion(MultiviewSession.previewProfile("I-Log", flat: false)))
        for flat in [true, false] {
            XCTAssertEqual(
                LunaShellMapping.previewColorMode(recording: .iLog, recoveryOff: flat) == .iLog,
                MultiviewSession.previewProfile("I-Log", flat: flat) == "I-Log",
                "tiles and Live View agree on what the I-Log preview carries")
        }
    }

    func testNoTileWritesWithoutTheEditorsLeaseOrABorrowedLiveView() {
        let stage = session()
        let tile = stage.tiles[0]
        XCTAssertFalse(tile.session.admitsMultiviewControl, "no editor: a late drum change is refused")
        XCTAssertNotNil(
            tile.session.multiviewDispatchAdmission(), "every tile write carries the stage's gate to dispatch")
        tile.controlsModel = AppModel(session: tile.session)
        XCTAssertFalse(tile.session.admitsMultiviewControl, "an editor without the stage's lease")
        tile.retireControls()
        XCTAssertNil(tile.controlsModel)
        XCTAssertFalse(tile.previewDemand)
        tile.liveModel = AppModel(session: tile.session)
        XCTAssertTrue(tile.session.admitsMultiviewControl, "Live View's monitor writes as the monitor does")
        stage.closeLiveView()
        XCTAssertFalse(tile.session.admitsMultiviewControl)
    }

    func testAnEditorOpensOnlyWhereTheStageAdmitsControls() {
        let stage = session()
        stage.openCameraSettings(slot: 0)
        XCTAssertNil(stage.tiles[0].controlsModel, "an empty slot has no editor")
        XCTAssertNil(stage.tiles[0].editorLease)
    }

    func testLiveViewIsABorrowedMonitorAndItsCloseReturnsTheTile() throws {
        let stage = session()
        let tile = stage.tiles[1]
        tile.member.camera = NearbyCamera(
            id: UUID().uuidString, name: "Luna A1B2", model: "Insta360 Luna Ultra", routes: [.cameraAccessPoint])
        tile.member.lutEnabled = true
        XCTAssertTrue(stage.openLiveView(slot: 1))
        let model = try XCTUnwrap(tile.liveModel)
        XCTAssertNotNil(model.shell.monitor, "volume-key record and the monitor rules see a monitor")
        XCTAssertEqual(model.shell.monitor?.session.id, tile.link.session.id)
        XCTAssertTrue(model.assist.lutEnabled)
        XCTAssertTrue(model.frameSamples === tile.samples)
        model.assist.lutEnabled = false
        // The shell's close returns the loan: the stage gets its tile back.
        model.shell.close()
        XCTAssertNil(tile.liveModel)
        XCTAssertFalse(tile.member.lutEnabled)
        XCTAssertEqual(tile.session.control.session?.id, tile.link.session.id, "the tile's controls follow its camera again")
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

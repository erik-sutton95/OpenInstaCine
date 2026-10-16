import Foundation
import Insta360Apple
import Insta360AppleTestSupport
import OpenCineAppKit
import OpenCineCore
import OpenCineHostedTestSupport
import XCTest

@testable import OpenInstaCine

/// SHELL-02 migration tests 1-6 on golden fixtures that the shipping app's encoder wrote
/// (`SavedCameraStore.save`: JSONEncoder over `[SavedCamera]`, dates in seconds since 2001),
/// through the app's own store wiring (`AppModel.camerasStore`).
@MainActor
final class SavedCamerasMigrationTests: XCTestCase {
    private let a = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    private let b = "7A1B2C3D-4E5F-4061-8293-A4B5C6D7E8F9"
    private let c = "0D1E2F30-4152-4637-8899-AABBCCDDEEFF"
    private let d = "99999999-2222-4333-8444-555555555555"
    private let legacyKey = "OpenInstaCine.SavedCameras"
    private let documentKey = "OpenInstaCine.Cameras"
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "shell02.migration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// The golden fixtures ship in the test bundle's resources: a device bundle has no
    /// source tree, so the `#filePath`-relative lookup only works where the sources do.
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
            "The \(name) fixture must ship in the test bundle")
        return try Data(contentsOf: url)
    }

    private func loaded(_ legacy: String) throws -> SavedCamerasStore {
        defaults.set(try fixture(legacy), forKey: legacyKey)
        let store = AppModel.camerasStore(defaults)
        store.load()
        return store
    }

    private var storedKeys: Set<String> { Set((defaults.persistentDomain(forName: suite) ?? [:]).keys) }
    private func milliseconds(_ date: Date?) -> Int64? { date.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } }

    /// The decoder every released build runs: the synthesized Codable of the app's old record.
    private struct OldRecord: Codable {
        enum Setup: String, Codable { case cameraWiFi, wifi, phoneHotspot }
        var id: UUID
        var advertisedName: String
        var modelName: String
        var modelId: Int?
        var lastSSID: String?
        var lastConnectedAt: Date
        var customName: String?
        var wifiSSID: String?
        var hotspotSSID: String?
        var lastSetup: Setup?
    }

    // 1
    func testUpgradeImportsEveryCameraAndLeavesLegacyAlone() throws {
        let store = try loaded("legacy")
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"))
        XCTAssertEqual(storedKeys, [legacyKey, documentKey], "nothing else is written; credentials stay in the Keychain")
        XCTAssertEqual(store.cameras.map(\.id), [a, b, c])
        XCTAssertTrue(store.cameras.allSatisfy { $0.integration == LunaCameraSession.integration && $0.device == nil })

        let first = store.cameras[0]
        XCTAssertEqual(first.name, "A cam")
        XCTAssertEqual(first.advertisedName, "Luna Ultra 1A2B3C")
        XCTAssertEqual(first.model, "Luna Ultra")
        XCTAssertEqual(first.routes.map(\.kind), [.cameraAccessPoint])
        XCTAssertEqual(first.routes.map(\.network), ["LUNA-1A2B3C"])
        XCTAssertEqual(first.preferredRoute, first.routes[0].id)
        XCTAssertEqual(milliseconds(first.lastConnected), 1_759_307_200_250)
        XCTAssertEqual(first.extras, [:])

        // Station setups an older shell stored round-trip as routes.
        let second = store.cameras[1]
        XCTAssertNil(second.name)
        XCTAssertEqual(second.routes.map(\.key), ["ap", "wifi", "hotspot"])
        XCTAssertEqual(second.routes.map(\.network), ["LUNA-4D5E6F", "Studio", "Rig iPhone"])
        XCTAssertEqual(second.preferredRoute, second.routes[0].id)

        let third = store.cameras[2]
        XCTAssertEqual(third.routes.map(\.key), ["ap"])
        XCTAssertNil(third.routes[0].network)
        XCTAssertNil(third.preferredRoute)
        XCTAssertEqual(milliseconds(third.lastConnected), 1_757_307_200_500)

        let document = try XCTUnwrap(defaults.data(forKey: documentKey))
        let decoded = try JSONSerialization.jsonObject(with: document) as? [String: Any]
        XCTAssertEqual(decoded?["version"] as? Int, 1)
    }

    // 2
    func testMigrationIsIdempotent() throws {
        let first = try loaded("legacy")
        let document = defaults.data(forKey: documentKey)
        for _ in 0..<2 {
            let again = AppModel.camerasStore(defaults)
            again.load()
            XCTAssertEqual(again.cameras, first.cameras)
        }
        XCTAssertEqual(defaults.data(forKey: documentKey), document)
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"))
        XCTAssertEqual(storedKeys, [legacyKey, documentKey])
    }

    // 3: rename, forget, connect and a new pair through the shared model, then the older build
    // reads the mirror with its own decoder.
    func testMirrorRoundTripDecodesWithTheOldDecoder() async throws {
        defaults.set(try fixture("legacy"), forKey: legacyKey)
        let port = FakeLunaPort()
        let connectedAt = Date(timeIntervalSinceReferenceDate: 790_000_000)
        let model = CamerasModel(
            integrations: [AppIntegration(LunaIntegration(port: port, now: { connectedAt }))],
            store: AppModel.camerasStore(defaults))
        model.rename(a, to: "Renamed")
        await model.forget(c)
        XCTAssertEqual(port.forgotten.map(\.uuidString), [c], "forget drops the camera's saved Wi-Fi")

        model.connect(try XCTUnwrap(model.saved.first { $0.id == b }))
        try await until { port.connects.count == 1 }
        port.connectedSerial = "SN-B"
        port.finishConnect()
        try await until { model.saved.first { $0.id == b }?.lastConnected == connectedAt }
        model.sessionEnded()
        port.connectedSerial = nil

        port.emit(.discovered(MonitorCamera(id: UUID(uuidString: d)!, name: "AABBCC", model: "", capabilities: [])))
        try await until { !model.nearby.isEmpty }
        port.joinedNetwork = "LUNA-AABBCC"
        model.connect(model.nearby[0])
        try await until { port.connects.count == 2 }
        port.finishConnect()
        try await until { model.saved.count == 3 }

        let legacy = try XCTUnwrap(defaults.data(forKey: legacyKey))
        let old = try JSONDecoder().decode([OldRecord].self, from: legacy)
        XCTAssertEqual(old.map(\.id.uuidString), [a, b, d])
        XCTAssertEqual(old[0].customName, "Renamed")
        XCTAssertEqual(old[0].lastSetup, .cameraWiFi)
        XCTAssertEqual(old[1].lastConnectedAt, connectedAt)
        XCTAssertEqual(old[1].wifiSSID, "Studio")
        XCTAssertEqual(old[1].hotspotSSID, "Rig iPhone")
        XCTAssertEqual(old[2].advertisedName, "Luna Ultra AABBCC")
        XCTAssertEqual(old[2].modelName, "Luna Ultra")
        XCTAssertEqual(old[2].lastSSID, "LUNA-AABBCC")
        XCTAssertEqual(old[2].lastSetup, .cameraWiFi)

        // The serial lives only in the document; a reload keeps it as saved.
        let again = AppModel.camerasStore(defaults)
        again.load()
        XCTAssertEqual(again.cameras, model.saved)
        XCTAssertEqual(again.cameras.first { $0.id == b }?.device, .durable("SN-B", integration: LunaCameraSession.integration))
    }

    // 4
    func testDowngradeEditsMergeBackOnUpgrade() throws {
        let store = try loaded("legacy")
        var cameras = store.cameras
        cameras[0].device = .durable("SN-A", integration: LunaCameraSession.integration)
        store.save(cameras)
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"), "a document-only edit leaves legacy alone")
        let apRoute = cameras[0].routes[0].id

        // The older build renamed B, forgot C, paired D and added a Wi-Fi setup to A.
        defaults.set(try fixture("legacy-downgrade-edits"), forKey: legacyKey)
        let upgraded = AppModel.camerasStore(defaults)
        upgraded.load()
        XCTAssertEqual(Set(upgraded.cameras.map(\.id)), [a, b, d])
        let first = try XCTUnwrap(upgraded.cameras.first { $0.id == a })
        XCTAssertEqual(first.device, .durable("SN-A", integration: LunaCameraSession.integration))
        XCTAssertEqual(first.routes.map(\.key), ["ap", "wifi"])
        XCTAssertEqual(first.routes[0].id, apRoute)
        XCTAssertEqual(first.routes[1].network, "Office")
        XCTAssertEqual(first.preferredRoute, first.routes[1].id)
        XCTAssertEqual(upgraded.cameras.first { $0.id == b }?.name, "B cam")
        let fourth = try XCTUnwrap(upgraded.cameras.first { $0.id == d })
        XCTAssertEqual(fourth.routes.map(\.network), ["LUNA-AABBCC"])
        XCTAssertEqual(fourth.preferredRoute, fourth.routes[0].id)
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy-downgrade-edits"))
    }

    func testSetupRenameSurvivesOlderBuildEditsAndCanBeCleared() throws {
        _ = try loaded("legacy")
        let model = CamerasModel(integrations: [], store: AppModel.camerasStore(defaults))
        let original = try XCTUnwrap(model.saved.first { $0.id == a })
        let route = try XCTUnwrap(original.routes.first)
        model.renameRoute(route.id, of: a, to: "  Location A  ")
        XCTAssertEqual(model.saved.first { $0.id == a }?.routes.first?.title, "Location A")
        XCTAssertEqual(defaults.data(forKey: legacyKey), try fixture("legacy"))

        // The older format has no setup-title field. Its camera and network edits must
        // preserve the new title and stable route identity when this app is reinstalled.
        defaults.set(try fixture("legacy-downgrade-edits"), forKey: legacyKey)
        let upgraded = CamerasModel(integrations: [], store: AppModel.camerasStore(defaults))
        let camera = try XCTUnwrap(upgraded.saved.first { $0.id == a })
        XCTAssertEqual(camera.routes.first?.id, route.id)
        XCTAssertEqual(camera.routes.first?.title, "Location A")
        XCTAssertEqual(camera.routes.last?.network, "Office")
        let preferred = camera.preferredRoute
        upgraded.renameRoute(route.id, of: a, to: " ")
        let again = AppModel.camerasStore(defaults)
        again.load()
        let cleared = try XCTUnwrap(again.cameras.first { $0.id == a })
        XCTAssertNil(cleared.routes.first?.title)
        XCTAssertEqual(cleared.routes.first?.id, route.id)
        XCTAssertEqual(cleared.preferredRoute, preferred)
        XCTAssertEqual(storedKeys, [legacyKey, documentKey])
    }

    // 5
    func testABadRecordIsKeptAndNeverOverwritten() throws {
        let store = try loaded("legacy-bad-record")
        XCTAssertEqual(store.cameras.map(\.id), [a, b, c])
        var cameras = store.cameras
        cameras[0].name = "Renamed"
        store.save(cameras)
        let raw = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: legacyKey))) as? [[String: Any]])
        XCTAssertEqual(raw.count, 4)
        XCTAssertEqual(raw[0]["customName"] as? String, "Renamed")
        XCTAssertNil(raw[3]["id"])
        XCTAssertEqual(raw[3]["advertisedName"] as? String, "Broken")
        XCTAssertEqual((raw[3]["futureField"] as? [String: Any])?["kept"] as? Bool, true)
    }

    // 6
    func testADocumentFromANewerBuildIsNeverWritten() throws {
        let future = Data(#"{"cameras":[],"legacy":{},"version":2}"#.utf8)
        defaults.set(future, forKey: documentKey)
        let store = try loaded("legacy")
        XCTAssertFalse(store.writesDocument)
        XCTAssertEqual(store.cameras.map(\.id), [a, b, c], "this build runs from legacy")
        var cameras = store.cameras
        cameras[1].name = "Edited"
        store.save(cameras)
        XCTAssertEqual(defaults.data(forKey: documentKey), future)
        let old = try JSONDecoder().decode([OldRecord].self, from: XCTUnwrap(defaults.data(forKey: legacyKey)))
        XCTAssertEqual(old[1].customName, "Edited")
    }

    private func until(_ condition: @MainActor @Sendable () -> Bool) async throws {
        let held = await HostedCondition.wait(until: condition)
        XCTAssertTrue(held)
    }
}

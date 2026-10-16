import Foundation
import Observation
import OpenCineAppKit
import XCTest

@testable import OpenInstaCine

private final class SettingsCacheFileManager: FileManager, @unchecked Sendable {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let condition = NSCondition()
    private var held = true
    private var fail = false
    private var blocked: XCTestExpectation?

    func arm(_ expectation: XCTestExpectation) {
        condition.lock(); blocked = expectation; condition.unlock()
    }
    func release(failing: Bool = false) {
        condition.lock(); fail = failing; held = false; condition.broadcast(); condition.unlock()
    }
    override func removeItem(at url: URL) throws {
        if url.lastPathComponent.hasPrefix(".clearing-zz-secondary-") {
            condition.lock()
            let notification = blocked
            blocked = nil
            notification?.fulfill()
            while held { condition.wait() }
            let shouldFail = fail
            condition.unlock()
            if shouldFail {
                throw NSError(domain: "SIMULATED Settings cache", code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "SIMULATED secondary deletion failed"])
            }
        }
        try super.removeItem(at: url)
    }
}

@MainActor private final class CacheReadoutWatcher {
    let predicate: () -> Bool
    let fulfill: () -> Void
    private var finished = false
    init(predicate: @escaping () -> Bool, fulfill: @escaping () -> Void) {
        self.predicate = predicate; self.fulfill = fulfill
    }
    func start() {
        guard !finished else { return }
        let ready = withObservationTracking { predicate() } onChange: {
            Task { @MainActor [weak self] in self?.start() }
        }
        if ready { finished = true; fulfill() }
    }
}

/// SIMULATED held real filesystem deletion through the actual shipping Settings source factory.
@MainActor final class SettingsCacheAdapterTests: XCTestCase {
    private func waitFor(_ description: String, _ predicate: @escaping () -> Bool) async {
        let done = expectation(description: description)
        let watcher = CacheReadoutWatcher(predicate: predicate, fulfill: { done.fulfill() })
        watcher.start()
        await fulfillment(of: [done], timeout: 5)
        withExtendedLifetime(watcher) {}
        XCTAssertTrue(predicate(), description)
    }

    func testDelayedOtherBucketClearRecountsAfterCurrentLibraryRevision() async throws {
        try await clearScenario(failing: false)
    }
    func testDelayedOtherBucketFailureRemainsVisibleAndRetryRecounts() async throws {
        try await clearScenario(failing: true)
    }
    private func clearScenario(failing: Bool) async throws {
        let manager = SettingsCacheFileManager()
        let storage = MonitorMediaCacheStorage(fileManager: manager)
        let media = CameraMedia(fileManager: manager, storage: storage, cacheRoot: manager.parent)
        let session = CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder(),
            cameraMedia: media, mediaStorage: storage, controlsOnly: true)
        let model = AppModel(session: session)
        let cache = MonitorSettingsCacheModel()
        defer {
            manager.release()
            cache.retire()
            model.delivery.close()
            session.decoder.close()
            try? FileManager.default.removeItem(at: manager.parent)
        }
        let current = session.mediaLibrary.cache.directory
        let other = storage.directory(root: manager.parent.appendingPathComponent("zz-secondary"))
        try current.write(Data(repeating: 1, count: 4096), at: "fixture.bin")
        try other.write(Data(repeating: 2, count: 8192), at: "fixture.bin")
        cache.refresh(model.settingsCacheSource)
        await waitFor("Initial actual all-camera bytes") { cache.bytes == 12288 }
        let revision = session.mediaCacheRevision
        let blocked = expectation(description: "Second actual bucket deletion is held")
        manager.arm(blocked)
        cache.requestClear(); cache.clear()
        await fulfillment(of: [blocked], timeout: 5)
        XCTAssertNotEqual(session.mediaCacheRevision, revision)
        let partial = await media.cacheByteCountAllCameras()
        XCTAssertEqual(partial, 8192)
        // SwiftUI renews the shipping source when that observed content revision changes.
        cache.refresh(model.settingsCacheSource)
        await waitFor("Renewed source counts remaining actual bytes") { cache.bytes == 8192 }
        manager.release(failing: failing)
        await waitFor("Captured Clear completes") { !cache.clearing }
        if failing {
            let remaining = await media.cacheByteCountAllCameras()
            XCTAssertEqual(remaining, 8192)
            await waitFor("Failed Clear recounts remaining actual bytes") { cache.bytes == 8192 }
            XCTAssertEqual(cache.bytes, 8192)
            XCTAssertTrue(cache.clearFailed)
            XCTAssertEqual(cache.failure, "SIMULATED secondary deletion failed")
            manager.release()
            cache.refresh(model.settingsCacheSource)
            cache.requestClear(); cache.clear()
            await waitFor("Retry Clear completes") { !cache.clearing }
        }
        let remaining = await media.cacheByteCountAllCameras()
        XCTAssertEqual(remaining, 0)
        await waitFor("Final readout matches actual bytes") { cache.bytes == 0 }
        XCTAssertFalse(cache.clearFailed)
        XCTAssertNil(cache.failure)
    }
}

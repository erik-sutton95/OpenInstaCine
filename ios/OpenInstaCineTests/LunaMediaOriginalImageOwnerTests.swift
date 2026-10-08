import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineAppKit
import OpenCineMedia
import OpenInstaViewCore
import XCTest
import os

@testable import OpenInstaCine

/// SIMULATED real HTTP plus Library IO and a Luna session epoch. The backend TCP handshake is
/// deliberately not simulated as ready; its actual facade refusal is separately asserted.
@MainActor final class LunaMediaOriginalImageOwnerTests: XCTestCase {
    func testNativeOriginalPreservesRoutedAddressBytesCacheAndShotColor() async throws {
        let fixture = LunaOriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "/DCIM/ORIGINAL.JPG", thumbPath: "/DCIM/THUMB.JPG", sizeBytes: 4, storage: 1)
        try fixture.seed(file)
        fixture.media.rememberShotColor(.iLog, path: file.path, cameraID: fixture.facade.mediaCameraID)
        let expected = try XCTUnwrap(MediaHTTP.pathURL(storage: file.storage, path: file.path, route: fixture.facade.profile.media))
        let bytes = Data([0, 1, 255, 9])
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init(payload: bytes) }
        defer { LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let record = try XCTUnwrap(fixture.facade.mediaRecord(for: file))
        for address in record.address.representations.values { try fixture.facade.mediaLibrary.cache.directory.write(Data([7]), at: address) }
        if let thumbnail = record.address.thumbnail { try fixture.facade.mediaLibrary.cache.directory.write(Data([8]), at: thumbnail) }
        let value = try await fixture.read(file)
        XCTAssertEqual(value, bytes)
        XCTAssertEqual(LunaOriginalImageOwnerURLProtocol.state.withLock { $0.requests }, [expected])
        for address in record.address.representations.values { XCTAssertEqual(try fixture.facade.mediaLibrary.cache.directory.read(address), Data([7])) }
        if let thumbnail = record.address.thumbnail { XCTAssertEqual(try fixture.facade.mediaLibrary.cache.directory.read(thumbnail), Data([8])) }
        XCTAssertEqual(fixture.facade.shotColor(for: file), .iLog)
        XCTAssertEqual(fixture.facade.mediaLibrary.records.map { $0.payload.file }, [file])
        XCTAssertTrue(fixture.facade.mediaLibrary.hostProgress.isEmpty)
    }

    func testActualFacadeDoesNotInventBackendReadinessFromFixtureSession() async throws {
        let fixture = LunaOriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "/DCIM/NOT_READY.JPG", thumbPath: "/DCIM/THUMB.JPG")
        try fixture.seed(file)
        fixture.facade.phase = .live
        fixture.facade.lunaSessionOverride = fixture.source
        XCTAssertTrue(fixture.source.admitsControl)
        XCTAssertFalse(fixture.facade.canReachCameraMedia)
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() }
        defer { LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let bytes = await fixture.facade.originalImageBytes(for: file, ifCurrent: { true })
        XCTAssertNil(bytes)
        XCTAssertTrue(LunaOriginalImageOwnerURLProtocol.state.withLock { $0.requests.isEmpty })
        XCTAssertTrue(fixture.facade.mediaLibrary.hostProgress.isEmpty)
    }

    func testLibraryCloseCancelsActualNativeOriginalHTTPRequest() async throws {
        let fixture = LunaOriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "/DCIM/CLOSE.JPG", thumbPath: "/DCIM/THUMB.JPG")
        try fixture.seed(file)
        let ready = expectation(description: "Actual original HTTP is pending")
        let stopped = expectation(description: "Library close stops original HTTP")
        let completed = expectation(description: "Retired Library read does not wait for image body")
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { let bytes = try? await fixture.read(file); completed.fulfill(); return bytes }
        await fulfillment(of: [ready], timeout: 5)
        fixture.facade.mediaLibrary.close()
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = LunaOriginalImageOwnerURLProtocol.state.withLock { $0.didStop }
        if !cancelled { LunaOriginalImageOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled, "Retirement must cancel underlying camera HTTP")
        XCTAssertNil(bytes)
        XCTAssertTrue(fixture.facade.mediaLibrary.hostProgress.isEmpty)
    }

    func testCallerCancellationStopsActualNativeOriginalHTTPRequest() async throws {
        let fixture = LunaOriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "/DCIM/CANCEL.JPG", thumbPath: "/DCIM/THUMB.JPG")
        try fixture.seed(file)
        let ready = expectation(description: "Actual original HTTP is pending")
        let stopped = expectation(description: "Caller cancellation stops original HTTP")
        let completed = expectation(description: "Cancelled Library read does not wait for image body")
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { let bytes = try? await fixture.read(file); completed.fulfill(); return bytes }
        await fulfillment(of: [ready], timeout: 5)
        request.cancel()
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = LunaOriginalImageOwnerURLProtocol.state.withLock { $0.didStop }
        if !cancelled { LunaOriginalImageOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled); XCTAssertNil(bytes)
        XCTAssertTrue(fixture.facade.mediaLibrary.hostProgress.isEmpty)
    }

    func testSameNativeSessionNewEpochRejectsDelayedOriginalThenAdmitsSuccessor() async throws {
        let fixture = LunaOriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "/DCIM/EPOCH.JPG", thumbPath: "/DCIM/THUMB.JPG")
        try fixture.seed(file)
        let ready = expectation(description: "Captured native epoch original is pending")
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready) }
        defer { LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { try? await fixture.read(file) }
        await fulfillment(of: [ready], timeout: 5)
        let epoch = fixture.source.current.epoch
        fixture.source.linkChanged(.idle, serial: nil)
        fixture.source.linkChanged(.streaming, serial: "SIMULATED-ORIGINAL")
        XCTAssertNotEqual(fixture.source.current.epoch, epoch)
        let pending = try XCTUnwrap(LunaOriginalImageOwnerURLProtocol.state.withLock { $0.pending })
        pending.finishBody(); let old = await request.value
        XCTAssertNil(old)
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init(payload: Data([9])) }
        let current = try await fixture.read(file)
        XCTAssertEqual(current, Data([9]))
        XCTAssertTrue(fixture.facade.mediaLibrary.hostProgress.isEmpty)
    }

    func testActualRecordRemovalCancelsNativeOriginalWithoutPublishingBytes() async throws {
        let fixture = LunaOriginalImageOwnerFixture()
        defer { fixture.close() }
        let file = MediaFile(path: "/DCIM/REMOVED.JPG", thumbPath: "/DCIM/THUMB.JPG")
        try fixture.seed(file)
        let ready = expectation(description: "Known record original is pending")
        let stopped = expectation(description: "Record removal stops original HTTP")
        let completed = expectation(description: "Retired record cannot publish its original")
        LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init(hold: true, ready: ready, stopped: stopped) }
        defer { LunaOriginalImageOwnerURLProtocol.state.withLock { $0 = .init() } }
        let request = Task { let bytes = try? await fixture.read(file); completed.fulfill(); return bytes }
        await fulfillment(of: [ready], timeout: 5)
        let library = try XCTUnwrap(fixture.facade.mediaLibrary)
        try library.applyLocalRecords(.init(resetLibrary: true, upserts: []), token: library.actionToken)
        await fulfillment(of: [stopped, completed], timeout: 5)
        let cancelled = LunaOriginalImageOwnerURLProtocol.state.withLock { $0.didStop }
        if !cancelled { LunaOriginalImageOwnerURLProtocol.state.withLock { $0.pending }?.finishBody() }
        let bytes = await request.value
        XCTAssertTrue(cancelled); XCTAssertNil(bytes)
        XCTAssertTrue(library.records.isEmpty && library.hostProgress.isEmpty)
    }
}

@MainActor private final class LunaOriginalImageOwnerFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let media: CameraMedia
    let facade: OpenInstaCine.CameraSession
    let source: LunaCameraSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LunaOriginalImageOwnerURLProtocol.self]
        media = CameraMedia(httpConfiguration: configuration, storage: MonitorMediaCacheStorage(), cacheRoot: root)
        facade = OpenInstaCine.CameraSession(backend: AppModel.makeBackend(), borrowing: HevcDecoder(), cameraMedia: media, controlsOnly: true)
        source = LunaCameraSession(send: { _ in Data() }, functionMode: { LunaFunctionMode.normalVideo.rawValue },
            readSettings: {}, readCapture: {})
        source.linkChanged(.streaming, serial: "SIMULATED-ORIGINAL")
    }
    func seed(_ file: MediaFile) throws {
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let records = try codec.decode(JSONEncoder().encode([file]))
        try facade.mediaLibrary.applyLocalRecords(.init(resetLibrary: true, upserts: records), token: facade.mediaLibrary.actionToken)
    }
    func read(_ file: MediaFile) async throws -> Data? {
        let library = try XCTUnwrap(facade.mediaLibrary)
        let record = try XCTUnwrap(facade.mediaRecord(for: file)), epoch = source.current.epoch
        let captured = source
        let authority = library.captureIO(key: .init(file.path), asset: record.asset.id) { [weak self] in
            guard let self, self.source === captured, captured.admitsControl,
                captured.current.epoch == epoch,
                self.facade.mediaRecord(for: file)?.asset.id == record.asset.id else { return false }
            return true
        }
        let url = try XCTUnwrap(MediaHTTP.pathURL(storage: file.storage, path: file.path, route: facade.profile.media))
        return try await library.readHostOriginalImage(authority) { [media] in
            try await media.nativeIO.originalImageBytes(from: url)
        }
    }
    func close() {
        facade.disconnect()
        facade.decoder.close()
        source.linkChanged(.idle, serial: nil)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class LunaOriginalImageOwnerURLProtocol: URLProtocol, @unchecked Sendable {
    struct State {
        var payload = Data([1, 2, 3])
        var hold = false
        var ready: XCTestExpectation?
        var stopped: XCTestExpectation?
        var requests: [URL] = []
        var pending: LunaOriginalImageOwnerURLProtocol?
        var didStop = false
    }
    static let state = OSAllocatedUnfairLock(initialState: State())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let captured = Self.state.withLock {
            $0.requests.append(url)
            $0.pending = self
            $0.didStop = false
            return ($0.hold, $0.ready)
        }
        captured.1?.fulfill()
        if !captured.0 { finishBody() }
    }
    func finishBody() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        let bytes = Self.state.withLock { $0.pending === self && !$0.didStop ? $0.payload : nil }
        guard let bytes else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        let stopped = Self.state.withLock {
            guard $0.pending === self, !$0.didStop else { return Optional<XCTestExpectation>.none }
            $0.didStop = true
            return $0.stopped
        }
        stopped?.fulfill()
    }
}

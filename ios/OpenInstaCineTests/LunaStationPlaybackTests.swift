import Foundation
import OpenCineAppKit
import OpenCineMedia
import OpenInstaViewCore
import XCTest
import os

@testable import OpenInstaCine

/// SIMULATED HTTP. On a Wi-Fi or hotspot setup the camera's own access point (192.168.42.1) is
/// gone, so every camera fetch a clip's playback falls back to must go to the address this
/// connection found the camera at. A request to the access point address never connects and
/// holds the player on "Preparing playback" until the request times out.
@MainActor final class LunaStationPlaybackTests: XCTestCase {
    func testCameraPlaybackFallbacksFetchFromTheConnectionsCameraAddress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StationPlaybackURLProtocol.self]
        let media = CameraMedia(httpConfiguration: configuration, storage: MonitorMediaCacheStorage(), cacheRoot: root)
        let session = OpenInstaCine.CameraSession(
            backend: AppModel.makeBackend(), borrowing: HevcDecoder(), cameraMedia: media, controlsOnly: true)
        StationPlaybackURLProtocol.requests.withLock { $0 = [] }
        defer {
            StationPlaybackURLProtocol.requests.withLock { $0 = [] }
            session.disconnect()
            session.decoder.close()
            try? FileManager.default.removeItem(at: root)
        }
        let file = MediaFile(
            path: "/storage_internal/DCIM/Camera01/VID_SIMULATED_021.mp4", thumbPath: "", sizeBytes: 4,
            durationSeconds: 2, resolution: "3840x2160", fps: 25,
            proxyPath: "/storage_internal/DCIM/Camera01/LRV_SIMULATED_021.lrv")
        let codec = LunaMediaCatalogCodec(source: nil, shotColor: { _ in nil })
        let records = try codec.decode(JSONEncoder().encode([file]))
        let library = try XCTUnwrap(session.mediaLibrary)
        try library.applyLocalRecords(.init(resetLibrary: true, upserts: records), token: library.actionToken)
        let record = try XCTUnwrap(session.mediaRecord(for: file))
        // The camera on a home router (TEST-NET address), files at their own paths.
        let station = MediaHTTP.Route(host: "192.0.2.50", addressing: .directPath)

        var fetched: [String] = []
        for candidate in session.playbackCandidates(record, cameraRoute: station) {
            guard case .download(_, _, let path, _, let transfer) = candidate else { continue }
            _ = try await transfer(DiscardingSink())
            fetched.append(path)
        }

        XCTAssertTrue(fetched.contains(file.path), "The original is a camera fallback")
        XCTAssertTrue(fetched.contains(try XCTUnwrap(file.proxyPath)), "The listed proxy is a camera fallback")
        let requests = StationPlaybackURLProtocol.requests.withLock { $0 }
        XCTAssertEqual(requests.count, fetched.count)
        XCTAssertEqual(Set(requests.compactMap(\.host)), ["192.0.2.50"])
    }
}

private struct DiscardingSink: MediaByteSink {
    func write(_ chunk: Data) async throws {}
}

private final class StationPlaybackURLProtocol: URLProtocol, @unchecked Sendable {
    static let requests = OSAllocatedUnfairLock(initialState: [URL]())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requests.withLock { $0.append(url) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2, 3, 4]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

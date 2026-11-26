import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineApple
import OpenCineCore
import OpenCineMedia
import XCTest
import os

@testable import OpenInstaCine

/// On a Wi-Fi or hotspot setup the Luna answers every file request with 503 "service restricted"
/// (Luna Ultra fw 1.2.7); on its own Wi-Fi it serves them. The app says so where a clip, an
/// original, Save or Share needs the camera's file bytes, instead of failing generically.
@MainActor final class CameraFileAccessTests: XCTestCase {
    private let home = LunaStationNetwork(ssid: "Home", password: "SIMULATED", hotspot: false)
    private let station = "192.0.2.50"  // TEST-NET: the camera on a router.

    func testTheRouteDecidesAndARefusalOnlyCountsOnTheCamerasOwnWiFi() {
        XCTAssertEqual(CameraFileAccess.resolve(cameraHost: LunaProtocol.defaultHost, station: nil, refused: false), .available)
        XCTAssertEqual(CameraFileAccess.resolve(cameraHost: station, station: home, refused: false),
            .setupNetwork(network: "Home", hotspot: false))
        let hotspot = LunaStationNetwork(ssid: "Erik’s iPhone", password: "SIMULATED", hotspot: true)
        XCTAssertEqual(CameraFileAccess.resolve(cameraHost: "172.20.10.3", station: hotspot, refused: false),
            .setupNetwork(network: "Erik’s iPhone", hotspot: true))
        XCTAssertEqual(CameraFileAccess.resolve(cameraHost: station, station: nil, refused: false),
            .setupNetwork(network: nil, hotspot: false), "A station address without a known setup is still not the camera's Wi-Fi")
        XCTAssertEqual(CameraFileAccess.resolve(cameraHost: LunaProtocol.defaultHost, station: nil, refused: true), .refused)
        XCTAssertEqual(CameraFileAccess.resolve(cameraHost: station, station: home, refused: true),
            .setupNetwork(network: "Home", hotspot: false), "The route explains a refusal on a setup's network")
    }

    func testTheMessageNamesTheSetupAndTheDeviceAndNeverAdvisesAMacToJoinCameraWiFi() {
        XCTAssertNil(CameraFileAccess.available.message(host: .iPhone))
        XCTAssertEqual(CameraFileAccess.setupNetwork(network: "Home", hotspot: false).message(host: .iPhone),
            "Clips on the camera play over Camera Wi-Fi. On “Home” the Luna doesn’t share its files with this iPhone. Browsing and thumbnails still work.")
        XCTAssertEqual(CameraFileAccess.setupNetwork(network: "Home", hotspot: false).message(host: .mac),
            "On “Home” the Luna doesn’t share its files with this Mac. Browsing and thumbnails still work.")
        XCTAssertEqual(CameraFileAccess.setupNetwork(network: "Erik’s iPhone", hotspot: true).message(host: .iPhone),
            "Clips on the camera play over Camera Wi-Fi. On the hotspot the Luna doesn’t share its files with this iPhone. Browsing and thumbnails still work.")
        XCTAssertEqual(CameraFileAccess.setupNetwork(network: nil, hotspot: false).message(host: .iPad),
            "Clips on the camera play over Camera Wi-Fi. On this network the Luna doesn’t share its files with this iPad. Browsing and thumbnails still work.")
        XCTAssertEqual(CameraFileAccess.refused.message(host: .iPhone),
            "The Luna isn’t sharing its files with this iPhone right now. Browsing and thumbnails still work.",
            "A refusal on the camera's own Wi-Fi makes no route claim")
        for access in [CameraFileAccess.setupNetwork(network: "Home", hotspot: false), .refused] {
            for host in [HostDevice.iPhone, .iPad, .mac] {
                XCTAssertFalse(access.message(host: host)?.contains("\u{2014}") ?? true)
            }
        }
    }

    func testSaveAndShareAreHeldOnARouterButNotOnTheCamerasOwnWiFi() {
        let router = CameraFileAccess.resolve(cameraHost: station, station: home, refused: false)
        let accessPoint = CameraFileAccess.resolve(cameraHost: LunaProtocol.defaultHost, station: nil, refused: false)

        // The camera's own Wi-Fi: nothing changes (the pages keep their own answers).
        XCTAssertNil(accessPoint.heldActions(onDevice: false).share)
        XCTAssertNil(accessPoint.heldActions(onDevice: false).download)
        let open = accessPoint.playbackAccess(onDevice: false, deletes: true, deletable: true)
        XCTAssertEqual(open, .init(download: true, share: true, delete: true))

        // A router: an on-camera item neither saves nor shares; one on this device still shares.
        XCTAssertEqual(router.heldActions(onDevice: false).share, false)
        XCTAssertEqual(router.heldActions(onDevice: false).download, false)
        XCTAssertEqual(router.heldActions(onDevice: true).share, true)
        XCTAssertEqual(router.playbackAccess(onDevice: false, deletes: true, deletable: true),
            .init(download: false, share: false, delete: true), "Delete is a control-link command and stays")
        XCTAssertEqual(router.playbackAccess(onDevice: true, deletes: false, deletable: true),
            .init(download: false, share: true, delete: false))
        // The same rule after a "service restricted" answer on the camera's own Wi-Fi.
        XCTAssertEqual(CameraFileAccess.refused.heldActions(onDevice: false).share, false)
    }

    func testOnlyA503ServiceRestrictedBodyIsARefusal() {
        XCTAssertTrue(CameraFileRefusals.isServiceRestricted(status: 503, body: Data("service restricted".utf8)))
        XCTAssertTrue(CameraFileRefusals.isServiceRestricted(status: 503, body: Data("<html>Service Restricted</html>\n".utf8)))
        XCTAssertFalse(CameraFileRefusals.isServiceRestricted(status: 503, body: Data("busy".utf8)))
        XCTAssertFalse(CameraFileRefusals.isServiceRestricted(status: 404, body: Data("service restricted".utf8)))
        XCTAssertFalse(CameraFileRefusals.isServiceRestricted(status: 200, body: Data("service restricted".utf8)))
    }

    /// SIMULATED HTTP: the camera's 503 reaches the connection's refusals with its host, and a
    /// reconnect (a later baseline) starts clean. Another 503 body is not a refusal.
    func testTheTransportRecordsACamerasServiceRestrictedAnswer() async throws {
        let refusals = CameraFileRefusals()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefusingCameraURLProtocol.self]
        let io = LunaNativeMediaIO(configuration: configuration, refusals: refusals)
        let connected = refusals.sequence

        RefusingCameraURLProtocol.body.withLock { $0 = "busy" }
        let busy = try XCTUnwrap(URL(string: "http://192.168.42.1/DCIM/Camera01/VID_SIMULATED_001.mp4"))
        do { _ = try await io.transfer(from: busy, expectedByteCount: nil, into: DiscardingSink()); XCTFail("503 must fail") }
        catch { XCTAssertEqual(error as? MonitorMediaHTTPError, .status(503)) }
        XCTAssertFalse(refusals.refused(host: "192.168.42.1", after: connected))

        RefusingCameraURLProtocol.body.withLock { $0 = "service restricted" }
        let clip = try XCTUnwrap(URL(string: "http://192.168.42.1/storage_internal/DCIM/Camera01/VID_SIMULATED_002.mp4"))
        do { _ = try await io.transfer(from: clip, expectedByteCount: nil, into: DiscardingSink()); XCTFail("503 must fail") }
        catch { XCTAssertEqual(error as? MonitorMediaHTTPError, .status(503)) }
        XCTAssertTrue(refusals.refused(host: "192.168.42.1", after: connected))
        XCTAssertFalse(refusals.refused(host: "192.0.2.50", after: connected), "Another camera is not refused")

        let reconnected = refusals.sequence
        XCTAssertFalse(refusals.refused(host: "192.168.42.1", after: reconnected))
        let photo = try XCTUnwrap(URL(string: "http://192.168.42.1/DCIM/Camera01/IMG_SIMULATED_003.jpg"))
        do { _ = try await io.originalImageBytes(from: photo); XCTFail("503 must fail") }
        catch { XCTAssertEqual(error as? MonitorMediaHTTPError, .status(503)) }
        XCTAssertTrue(refusals.refused(host: "192.168.42.1", after: reconnected), "A photo original's refusal counts too")
    }
}

private struct DiscardingSink: MediaByteSink {
    func write(_ chunk: Data) async throws {}
}

/// The Luna on a router: every file request is answered 503 with `body`.
private final class RefusingCameraURLProtocol: URLProtocol, @unchecked Sendable {
    static let body = OSAllocatedUnfairLock(initialState: "service restricted")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"])
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.withLock { $0 }.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

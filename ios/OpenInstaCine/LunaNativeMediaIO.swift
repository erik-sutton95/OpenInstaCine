import Foundation
import Insta360Apple
import Insta360Protocol
import OpenCineApple
import OpenCineMedia

/// Source packet/address adapters only. Native copying/conversion and the library's owned sink
/// retain the request, byte storage and commit lifetimes.
@MainActor final class LunaNativeMediaIO: LunaMediaIO {
    private let stream: MonitorMediaHTTPStream
    private let originalImages: URLSession
    private let thumbnails = MonitorMediaThumbnailEncoder()
    /// Where this transport reports a camera that refuses its files.
    private let refusals: CameraFileRefusals
    init(configuration: URLSessionConfiguration = .ephemeral, refusals: CameraFileRefusals = .shared) {
        self.refusals = refusals
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.allowsCellularAccess = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        stream = MonitorMediaHTTPStream(configuration: configuration)
        originalImages = URLSession(configuration: configuration)
    }
    func jpeg(_ thumbnail: LunaThumbnail) async throws -> Data {
        guard let data = thumbnails.jpeg(width: thumbnail.width, height: thumbnail.height, nv12: thumbnail.nv12) else {
            throw MonitorMediaHTTPError.empty
        }
        return data
    }
    func transfer(from url: URL, into sink: any MediaByteSink) async throws -> MediaTransferReceipt {
        try await transfer(from: url, expectedByteCount: nil, into: sink)
    }
    func transfer(from url: URL, expectedByteCount: UInt64?, into sink: any MediaByteSink) async throws -> MediaTransferReceipt {
        do {
            return try await stream.transfer(from: url, expectedByteCount: expectedByteCount, into: sink)
        } catch MonitorMediaHTTPError.status(503) {
            // The stream drops a failed response's body. Read it once, so a camera that refuses
            // its files ("service restricted") is told apart from a busy one.
            try Task.checkCancellation()
            if let body = await refusalBody(url) { noteRefusal(url, status: 503, body: body) }
            throw MonitorMediaHTTPError.status(503)
        }
    }
    /// Raw single-image transport. The caller's Library task supplies source and record admission.
    func originalImageBytes(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        let (bytes, response) = try await originalImages.data(from: url)
        try Task.checkCancellation()
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
            noteRefusal(url, status: status, body: bytes)
            throw MonitorMediaHTTPError.status(status)
        }
        return bytes
    }
    /// The body of the camera's answer to one byte of `url`, when that answer is a 503.
    private func refusalBody(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 5
        guard let (body, response) = try? await originalImages.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 503 else { return nil }
        return body
    }
    private func noteRefusal(_ url: URL, status: Int, body: Data) {
        let text = String(decoding: body.prefix(160), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ControlLiveLog.line("media: camera answered \(status) for \(url.path) body=\"\(text)\"")
        guard CameraFileRefusals.isServiceRestricted(status: status, body: body), let host = url.host else { return }
        refusals.record(host: host)
    }
}

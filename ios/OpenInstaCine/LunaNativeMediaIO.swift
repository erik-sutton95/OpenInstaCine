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
    init(configuration: URLSessionConfiguration = .ephemeral) {
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
        try await stream.transfer(from: url, expectedByteCount: expectedByteCount, into: sink)
    }
    /// Raw single-image transport. The caller's Library task supplies source and record admission.
    func originalImageBytes(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        let (bytes, _) = try await originalImages.data(from: url)
        try Task.checkCancellation()
        return bytes
    }
}

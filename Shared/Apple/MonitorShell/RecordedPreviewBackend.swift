#if DEBUG
import AVFoundation
import Foundation
import MonitorContracts
import UIKit

/// Local validation adapter. The same unmodified monitor, scopes and media UI
/// consume this backend. It is absent from release builds and never claims a
/// local recording is a connected camera. No footage ships with the app.
@MainActor
public final class RecordedPreviewBackend: CameraBackend {
    private struct Index: Decodable {
        struct Packet: Decodable { let offset: Int; let size: Int }
        let videoPath: String
        let mediaPath: String?
        let framesPerSecond: Double
        let packets: [Packet]
    }
    public var eventHandler: ((CameraBackendEvent) -> Void)?
    public let capabilities: CameraCapabilities = [.liveVideo, .cameraMedia]
    public var isOnCameraNetwork: Bool { false }
    private let indexURL: URL
    private var index: Index?
    private var playback: Task<Void, Never>?
    private let camera = MonitorCamera(
        id: UUID(uuidString: "EC12FD48-A118-4A08-B825-49C2C1A0C142")!,
        name: "Local recording · preview test", model: "Recorded HEVC",
        capabilities: [.liveVideo, .cameraMedia])

    public init(indexURL: URL) { self.indexURL = indexURL }

    public func startScan() async throws {
        eventHandler?(.phase(.scanning))
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw CameraBackendError.unavailable("The local preview recording is missing.")
        }
        eventHandler?(.discovered(camera))
    }

    public func connect(to camera: MonitorCamera) async throws {
        disconnect()
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        guard index.framesPerSecond.isFinite, (1...120).contains(index.framesPerSecond),
              !index.packets.isEmpty, index.packets.count < 100_000 else {
            throw CameraBackendError.unavailable("The local preview index is invalid.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: index.videoPath), options: .mappedIfSafe)
        guard index.packets.allSatisfy({ $0.offset >= 0 && $0.size > 0 &&
            $0.offset <= data.count && $0.size <= data.count - $0.offset }) else {
            throw CameraBackendError.unavailable("The local preview recording is incomplete.")
        }
        self.index = index
        eventHandler?(.information(CameraInformation(model: "Recorded HEVC", sourceLabel: "LOCAL REPLAY", previewTransfer: .rec709)))
        eventHandler?(.phase(.streaming))
        playback = Task { [weak self] in
            var frame: UInt64 = 0
            let delay = UInt64(1_000_000_000 / index.framesPerSecond)
            while !Task.isCancelled {
                for packet in index.packets {
                    guard !Task.isCancelled, let self else { return }
                    self.eventHandler?(.videoAccessUnit(
                        data.subdata(in: packet.offset..<(packet.offset + packet.size)),
                        timestampMilliseconds: UInt64(Double(frame) * 1000 / index.framesPerSecond)))
                    frame += 1
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                }
            }
        }
    }

    public func disconnect() { playback?.cancel(); playback = nil; eventHandler?(.phase(.idle)) }
    public func forget(cameraID: UUID) {}
    public func leaveCameraNetwork() {}
    public func rejoinCameraNetwork() async throws {}

    public func listMedia() async throws -> [CameraMediaAsset] {
        guard let index, let path = index.mediaPath else { return [] }
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return [CameraMediaAsset(id: "local-preview-recording", filename: url.lastPathComponent,
            bytes: values.fileSize.map(UInt64.init),
            durationSeconds: Double(index.packets.count) / index.framesPerSecond,
            framesPerSecond: index.framesPerSecond)]
    }

    public func downloadMedia(_ asset: CameraMediaAsset, representation: CameraMediaRepresentation,
                              to destination: URL,
                              progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        guard asset.id == "local-preview-recording", let path = index?.mediaPath else {
            throw CameraBackendError.unavailable("The local preview recording is missing.")
        }
        try Task.checkCancellation()
        let source = URL(fileURLWithPath: path)
        if case .thumbnail = representation {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            let result = try await generator.image(at: .zero)
            guard let jpeg = UIImage(cgImage: result.image).jpegData(compressionQuality: 0.85) else {
                throw CameraBackendError.unavailable("The local thumbnail could not be rendered.")
            }
            try jpeg.write(to: destination)
        } else {
            try await Task.detached { try FileManager.default.copyItem(at: source, to: destination) }.value
        }
        try Task.checkCancellation()
        progress(1)
    }
}
#endif

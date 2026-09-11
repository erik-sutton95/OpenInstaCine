import Foundation

/// Camera-independent capabilities. Absence means the UI must not promise a camera operation.
public struct CameraCapabilities: OptionSet, Sendable, Equatable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let liveVideo = Self(rawValue: 1 << 0)
    public static let recording = Self(rawValue: 1 << 1)
    public static let exposure = Self(rawValue: 1 << 2)
    public static let captureFormat = Self(rawValue: 1 << 3)
    public static let whiteBalance = Self(rawValue: 1 << 4)
    public static let focus = Self(rawValue: 1 << 5)
    public static let zoom = Self(rawValue: 1 << 6)
    public static let gimbal = Self(rawValue: 1 << 7)
    public static let cameraMedia = Self(rawValue: 1 << 8)
    public static let liveAudio = Self(rawValue: 1 << 9)
}

public struct MonitorCamera: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let model: String
    public let capabilities: CameraCapabilities
    public init(id: UUID, name: String, model: String, capabilities: CameraCapabilities) {
        self.id = id
        self.name = name
        self.model = model
        self.capabilities = capabilities
    }
}

public enum CameraConnectionPhase: Sendable, Equatable {
    case idle, scanning, connecting, negotiating, awaitingApproval, readingWiFi, joiningWiFi,
        openingVideo, streaming
}

/// Capture metadata is deliberately separate from preview dimensions and delivery rate.
public enum CameraPreviewTransfer: String, Sendable, Codable {
    case rec709, hlg, dLog, dLog2, iLog
}

public struct CameraInformation: Sendable, Equatable {
    public var model: String
    public var firmware: String?
    public var sourceLabel: String?
    public var previewTransfer: CameraPreviewTransfer?
    public init(
        model: String, firmware: String? = nil, sourceLabel: String? = nil,
        previewTransfer: CameraPreviewTransfer? = nil
    ) {
        self.model = model
        self.firmware = firmware
        self.sourceLabel = sourceLabel
        self.previewTransfer = previewTransfer
    }
}

public enum CameraBackendEvent: Sendable {
    case discovered(MonitorCamera)
    case phase(CameraConnectionPhase)
    case information(CameraInformation)
    case status(CameraStatusSnapshot)
    case joinedWiFi(ssid: String)
    case videoAccessUnit(Data, timestampMilliseconds: UInt64)
    case disconnected(reason: String)
    case note(String)
}

/// The complete wire seam used by the shared Apple presentation facade.
/// Backends own authorization, credentials, network association and transport lifetime.
/// The UI owns decode/render, monitor assists, layout, library cache and operator preferences.
@MainActor
public protocol CameraBackend: AnyObject {
    var capabilities: CameraCapabilities { get }
    var eventHandler: ((CameraBackendEvent) -> Void)? { get set }
    var isOnCameraNetwork: Bool { get }
    func startScan() async throws
    func connect(to camera: MonitorCamera) async throws
    func disconnect()
    func forget(cameraID: UUID)
    func leaveCameraNetwork()
    func rejoinCameraNetwork() async throws
    func apply(_ intent: CameraControlIntent) async throws
    func refreshStatus() async throws
    func listMedia() async throws -> [CameraMediaAsset]
    func downloadMedia(
        _ asset: CameraMediaAsset, representation: CameraMediaRepresentation, to destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void) async throws
    func deleteMedia(_ asset: CameraMediaAsset) async throws
}

/// Explicit preview/test default; it never pretends to be a connected camera.
@MainActor
public final class UnavailableCameraBackend: CameraBackend {
    public let capabilities: CameraCapabilities = []
    public var eventHandler: ((CameraBackendEvent) -> Void)?
    public var isOnCameraNetwork: Bool { false }
    public init() {}
    public func startScan() async throws {
        throw CameraBackendError.unavailable("No camera adapter is configured.")
    }
    public func connect(to camera: MonitorCamera) async throws {
        throw CameraBackendError.unavailable("No camera adapter is configured.")
    }
    public func disconnect() { eventHandler?(.phase(.idle)) }
    public func forget(cameraID: UUID) {}
    public func leaveCameraNetwork() {}
    public func rejoinCameraNetwork() async throws {
        throw CameraBackendError.unavailable("No camera adapter is configured.")
    }
}

public enum CameraBackendError: LocalizedError, Sendable {
    case unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}

/// Stable semantic option identifier: for example "auto", "manual", "continuous".
/// It is never a camera opcode or an encoded numeric enum.
public struct CameraOption: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum CameraParameter: String, Sendable, Codable {
    case shootingMode, exposureMode, iso, isoCeiling, exposureCompensationStops, shutterSeconds
    case whiteBalanceMode, whiteBalanceKelvin, whiteBalanceTint, focusMode, focusTracking,
        focusOption
    case audioChannels, vocalBoost, windReduction, audioDirection, colorProfile, fieldOfView,
        facePriorityExposure
}
public enum CameraParameterValue: Sendable, Equatable {
    case automatic
    case boolean(Bool)
    case number(Double)
    case option(CameraOption)
}
public enum CameraControlIntent: Sendable, Equatable {
    case record(start: Bool)
    case takePhoto
    case parameter(CameraParameter, CameraParameterValue)
    case videoFormat(resolution: String, aspect: String, framesPerSecond: Double)
    case zoom(factor: Double)
    case gimbal(pan: Double, tilt: Double)
    case recenterGimbal, flipGimbal, stopGimbal
    case focus(x: Double, y: Double)
    case track(x: Double, y: Double, width: Double, height: Double)
    case stopTracking
    public var requiredCapability: CameraCapabilities {
        switch self {
        case .record, .takePhoto: .recording
        case .videoFormat: .captureFormat
        case .zoom: .zoom
        case .gimbal, .recenterGimbal, .flipGimbal, .stopGimbal: .gimbal
        case .focus, .track, .stopTracking: .focus
        case .parameter(let key, _):
            switch key {
            case .shootingMode, .colorProfile, .fieldOfView: .captureFormat
            case .whiteBalanceMode, .whiteBalanceKelvin, .whiteBalanceTint: .whiteBalance
            case .focusMode, .focusTracking, .focusOption: .focus
            case .audioChannels, .vocalBoost, .windReduction, .audioDirection: .liveAudio
            default: .exposure
            }
        }
    }
}

/// A snapshot is camera-reported state. Missing values remain unknown; applying a
/// user intent must not optimistically invent a recording state or capture format.
public struct CameraStatusSnapshot: Sendable, Equatable {
    public var batteryPercent: Int?
    public var charging: Bool?
    public var recording: Bool?
    public var recordedSeconds: Int?
    public var storageFreeBytes: UInt64?
    public var storageTotalBytes: UInt64?
    public var timecode: String?
    public var captureFramesPerSecond: Double?
    public var captureResolution: String?
    public var parameters: [CameraParameter: CameraParameterValue]
    public init(
        batteryPercent: Int? = nil, charging: Bool? = nil, recording: Bool? = nil,
        recordedSeconds: Int? = nil, storageFreeBytes: UInt64? = nil,
        storageTotalBytes: UInt64? = nil, timecode: String? = nil,
        captureFramesPerSecond: Double? = nil, captureResolution: String? = nil,
        parameters: [CameraParameter: CameraParameterValue] = [:]
    ) {
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.recording = recording
        self.recordedSeconds = recordedSeconds
        self.storageFreeBytes = storageFreeBytes
        self.storageTotalBytes = storageTotalBytes
        self.timecode = timecode
        self.captureFramesPerSecond = captureFramesPerSecond
        self.captureResolution = captureResolution
        self.parameters = parameters
    }
}

public struct CameraMediaAsset: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let filename: String
    public let bytes: UInt64?
    public let durationSeconds: Double?
    public let capturedAt: Date?
    public let resolution: String?
    public let framesPerSecond: Double?
    public let isPhoto: Bool
    public let canDelete: Bool
    public init(
        id: String, filename: String, bytes: UInt64? = nil, durationSeconds: Double? = nil,
        capturedAt: Date? = nil, resolution: String? = nil, framesPerSecond: Double? = nil,
        isPhoto: Bool = false, canDelete: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.bytes = bytes
        self.durationSeconds = durationSeconds
        self.capturedAt = capturedAt
        self.resolution = resolution
        self.framesPerSecond = framesPerSecond
        self.isPhoto = isPhoto
        self.canDelete = canDelete
    }
}
public enum CameraMediaRepresentation: Sendable, Equatable { case thumbnail, proxy, original }
extension CameraBackend {
    public func apply(_ intent: CameraControlIntent) async throws {
        throw CameraBackendError.unavailable("This camera control is not connected yet.")
    }
    public func refreshStatus() async throws {}
    public func listMedia() async throws -> [CameraMediaAsset] {
        throw CameraBackendError.unavailable("Camera media access is not connected yet.")
    }
    public func downloadMedia(
        _ asset: CameraMediaAsset, representation: CameraMediaRepresentation, to destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        throw CameraBackendError.unavailable("Camera media downloading is not connected yet.")
    }
    public func deleteMedia(_ asset: CameraMediaAsset) async throws {
        throw CameraBackendError.unavailable("Camera media deletion is not connected yet.")
    }
}

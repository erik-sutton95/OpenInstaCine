import Foundation

/// Verified bootstrap, live, photography GET/SET framing, and captured
/// gimbal-control commands. Color Recovery option 73 is framed the same way as
/// other photography SETs; firmware v1.0.288 has not stored a readable true.
public enum LunaCommand: UInt16, Sendable {
    case startLive = 1
    case stopLive = 2
    case takePicture = 3
    case startCapture = 4
    case stopCapture = 5
    case setOptions = 7
    case getOptions = 8
    case setPhotographyOptions = 9
    case getPhotographyOptions = 10
    case getFileExtra = 11
    case deleteFiles = 12
    case getFileList = 13
    case captureStatus = 15
    case checkAuthorization = 39
    case execCmd = 81
    case requestAuthorization = 86
    case getCameraParamsJSON = 216
    case setAccessCameraFileState = 118
    case gimbalControl = 226
    case openTracking = 237
    case cancelTracking = 238
    case encryptionCapabilities = 240
    case keyExchange = 241
}

/// Photography option numbers used by the official iOS app on Luna Ultra v1.0.288.
public enum LunaPhotographyType: UInt32, Sendable {
    case sharpness = 6
    case exposureBias = 7
    case videoExposure = 21
    case recordResolution = 31
    case colorMode = 35
    case whiteBalanceKelvin = 39
    case zoomScale = 53
    case iLogSwitch = 72
    case colorRecovery = 73
    case gimbalOptions = 91
    case afTrigger = 94
}

/// Device option 41 is the official-app shooting-mode write (not photography 31).
public enum LunaVideoSubMode: UInt64, Sendable {
    case normal = 0
    case timelapse = 2
    case timeShift = 4
    case slowMotion = 9
    case pureVideo = 11
}

public enum LunaColorMode: UInt64, Sendable {
    case standard = 1
    case iLog = 2
    case dolbyVision = 5
}

public enum LunaExposureProgram: UInt64, Sendable {
    case automatic = 0
    case isoPriority = 1
    case shutterPriority = 2
    case manual = 3
}

/// Captured `GimbalAction` values from official-app cmd 226.
public enum LunaGimbalAction: UInt64, Sendable {
    case move = 1
    case recenter = 2
    case flip = 3
}

public struct LunaRequest: Equatable, Sendable {
    public let command: LunaCommand
    public let body: Data
    public let requiresEncryption: Bool
    /// Wire MessageCode. Equals `command.rawValue` except for lab-issued raw codes.
    public let wireCode: UInt16

    public init(command: LunaCommand, body: Data, requiresEncryption: Bool) {
        self.command = command
        self.body = body
        self.requiresEncryption = requiresEncryption
        self.wireCode = command.rawValue
    }

    public init(code: UInt16, body: Data, requiresEncryption: Bool = false) {
        self.command = LunaCommand(rawValue: code) ?? .getOptions
        self.body = body
        self.requiresEncryption = requiresEncryption
        self.wireCode = code
    }

    public func message(identifier: UInt32) throws -> UCD2Message {
        guard identifier != 0 else { throw LunaProtocolError.invalidIdentifier }
        return try UCD2Message(code: wireCode, identifier: identifier, body: body,
                               identifierFlags: UCD2Message.requestFlags)
    }

    public func plainFrame(identifier: UInt32, sequence: UInt8) throws -> UCD2Frame {
        guard !requiresEncryption else { throw LunaProtocolError.responseEncryptionMismatch }
        return try UCD2Frame.plain(type: UCD2Frame.messageType, sequence: sequence,
                                   payload: message(identifier: identifier).payload)
    }
}

public struct LunaDeviceInformation: Equatable, Sendable {
    public let model: String
    public let firmware: String
    public let serial: String?
}

/// Do not persist in preferences or include in logs. The platform adapter owns
/// secure storage and Wi-Fi association, neither of which is performed here.
public struct LunaWiFiCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let ssid: String
    public let password: String
    public var description: String { "LunaWiFiCredentials(<redacted>)" }
    public var debugDescription: String { description }
}

public enum LunaAuthorizationStatus: UInt64, Sendable {
    case authorized = 0
    case approvalRequired = 1
}

/// Supplies fresh independent counters for a new BLE or TCP connection. Neither
/// identifies a client; persist a separate UUID for camera authorization.
public struct LunaRequestCounter: Sendable {
    private var identifier: UInt32 = 0
    private var sequence: UInt8 = 0
    public init() {}

    public mutating func nextIdentifier() -> UInt32 {
        identifier = identifier == UCD2Message.identifierMask ? 1 : identifier + 1
        return identifier
    }

    public mutating func nextSequence() -> UInt8 {
        sequence &+= 1
        return sequence
    }
}

public enum LunaProtocol {
    public static let model = "Insta360 Luna Ultra"
    public static let bluetoothServiceUUID = "0000BE80-0000-1000-8000-00805F9B34FB"
    public static let bluetoothWriteUUID = "0000BE81-0000-1000-8000-00805F9B34FB"
    public static let bluetoothNotifyUUID = "0000BE82-0000-1000-8000-00805F9B34FB"
    /// Conservative public-client chunk size, NOT a measured hardware maximum.
    public static let bluetoothWriteChunkSize = 206
    public static let defaultHost = "192.168.42.1"
    public static let defaultPort: UInt16 = 6666
    public static let heartbeatInterval: TimeInterval = 2
    public static let tcpPreface = Data([
        0x11, 0, 0, 0, 6, 0, 0, 0xAF, 0xFA, 0xAF, 0xFA, 0xAF, 0xFA, 0xAF, 0xFA, 0xAF, 0xFA
    ])
    public static let hkdfSalt = Data("UCD2-ENCRYPT".utf8)
    public static let hkdfInfo = Data("AES-SESSION-KEY".utf8)
    public static let sessionKeyByteCount = 16

    public static func getOptions(_ numbers: [UInt32], encrypted: Bool = false) throws -> LunaRequest {
        guard !numbers.isEmpty, numbers.count <= 256, numbers.allSatisfy({ $0 > 0 && $0 < 1 << 29 }) else {
            throw LunaProtocolError.malformedProtobuf
        }
        var body = Data()
        for number in numbers { body.append(try ProtoMessage.integer(field: 1, value: UInt64(number))) }
        return LunaRequest(command: .getOptions, body: body, requiresEncryption: encrypted)
    }

    public static func deviceInformationRequest(encrypted: Bool = false,
                                                 includeSerial: Bool = false) throws -> LunaRequest {
        try getOptions(includeSerial ? [48, 15, 30] : [48, 30], encrypted: encrypted)
    }

    public static let encryptionCapabilitiesRequest = LunaRequest(
        command: .encryptionCapabilities, body: Data(), requiresEncryption: false)

    public static func keyExchangeRequest(publicKey: Data) throws -> LunaRequest {
        try validatePublicKeyEncoding(publicKey)
        return LunaRequest(command: .keyExchange,
                           body: try ProtoMessage.integer(field: 1, value: 3)
                            + ProtoMessage.blob(field: 2, value: publicKey), requiresEncryption: false)
    }

    /// Mirrors the verified PHONE_IOS (1) initiator, including on macOS. Both
    /// identity fields are our same saved UUID, never an official-app identity.
    public static func authorizationCheck(identity: UUID) throws -> LunaRequest {
        let encoded = Data(identity.uuidString.uppercased().utf8)
        return LunaRequest(command: .checkAuthorization,
                           body: try ProtoMessage.blob(field: 1, value: encoded)
                            + ProtoMessage.integer(field: 2, value: 1)
                            + ProtoMessage.blob(field: 3, value: encoded), requiresEncryption: false)
    }

    public static let requestAuthorization = LunaRequest(
        command: .requestAuthorization, body: Data([8, 1]), requiresEncryption: false)

    public static let wifiCredentialsRequest = LunaRequest(
        command: .getOptions, body: Data([8, 36, 8, 37, 8, 43]), requiresEncryption: true)

    public static let captureStatusRequest = LunaRequest(
        command: .captureStatus, body: Data(), requiresEncryption: false)

    /// Captured and independently replayed v1.0.288 preview profile: HEVC,
    /// 1280x720, 25 fps. These field meanings are not inferred into UI controls.
    public static let startLiveRequest = LunaRequest(
        command: .startLive, body: Data([0x10, 1, 0x20, 0x80, 0xF7, 2, 0x38, 0x2B, 0x50, 0x0E, 0x60, 1]),
        requiresEncryption: false)

    public static let stopLiveRequest = LunaRequest(command: .stopLive, body: Data(), requiresEncryption: false)

    /// Official-app cmd 9 shape. Nested body is a PhotographyOptions protobuf.
    public static func setPhotographyOptions(types: [UInt32], nested: Data, mode: UInt32 = 7) throws -> LunaRequest {
        guard !types.isEmpty, types.count <= 256, types.allSatisfy({ $0 > 0 && $0 < 1 << 29 }) else {
            throw LunaProtocolError.malformedProtobuf
        }
        var packed = Data()
        for number in types { packed.append(ProtoMessage.varint(UInt64(number))) }
        let body = try ProtoMessage.blob(field: 1, value: packed)
            + ProtoMessage.blob(field: 2, value: nested)
            + ProtoMessage.integer(field: 3, value: UInt64(mode))
        return LunaRequest(command: .setPhotographyOptions, body: body, requiresEncryption: false)
    }

    /// Unsigned photography fields from a GET/SET reply's nested Options message.
    public static func photographyValues(_ response: Data) throws -> [Int: UInt64] {
        try photographyReading(response).integers
    }

    public struct PhotographyReading: Sendable, Equatable {
        public var integers: [Int: UInt64]
        public var blobs: [Int: Data]
        public var zoom: Double?
        public var iso: UInt64?
        public var shutterSeconds: Double?
        public var exposureProgram: UInt64?
    }

    public static func photographyReading(_ response: Data) throws -> PhotographyReading {
        guard let nested = try ProtoMessage(response).optionalBytes(2) else {
            return PhotographyReading(
                integers: [:], blobs: [:], zoom: nil, iso: nil, shutterSeconds: nil,
                exposureProgram: nil)
        }
        let options = try ProtoMessage(nested)
        var integers: [Int: UInt64] = [:]
        var blobs: [Int: Data] = [:]
        var zoom: Double?
        var iso: UInt64?
        var shutterSeconds: Double?
        var program: UInt64?
        for field in options.fields {
            switch field.value {
            case .unsigned(let value):
                integers[field.number] = value
            case .fixed64 where field.number == 53:
                zoom = try? options.double(53)
            case .bytes(let data) where field.number == 21:
                blobs[21] = data
                let exposure = try? ProtoMessage(data)
                program = try? exposure?.unsigned(1)
                iso = try? exposure?.unsigned(2)
                shutterSeconds = try? exposure?.double(3)
            case .bytes(let data):
                blobs[field.number] = data
            default:
                break
            }
        }
        return PhotographyReading(
            integers: integers, blobs: blobs, zoom: zoom, iso: iso, shutterSeconds: shutterSeconds,
            exposureProgram: program)
    }

    /// Official-app GET photography options. Field 2 is `FunctionMode` (7 = normal video).
    public static func getPhotographyOptions(_ types: [UInt32], mode: UInt32 = 7) throws -> LunaRequest {
        guard !types.isEmpty, types.count <= 256, types.allSatisfy({ $0 > 0 && $0 < 1 << 29 }) else {
            throw LunaProtocolError.malformedProtobuf
        }
        var body = Data()
        for number in types { body.append(try ProtoMessage.integer(field: 1, value: UInt64(number))) }
        body.append(try ProtoMessage.integer(field: 2, value: UInt64(mode)))
        return LunaRequest(command: .getPhotographyOptions, body: body, requiresEncryption: false)
    }

    /// Official-app cmd 226. Stick axes are protobuf sint32 zigzag, observed ±99.
    /// Zero axes encode an empty VirtualRC, matching captured release/center/flip.
    public static func gimbalControl(action: LunaGimbalAction, upDown: Int32 = 0,
                                     leftRight: Int32 = 0) throws -> LunaRequest {
        guard (-99...99).contains(upDown), (-99...99).contains(leftRight) else {
            throw LunaProtocolError.malformedProtobuf
        }
        var remote = Data()
        if upDown != 0 { remote.append(try ProtoMessage.signed32(field: 1, value: upDown)) }
        if leftRight != 0 { remote.append(try ProtoMessage.signed32(field: 2, value: leftRight)) }
        let body = try ProtoMessage.integer(field: 1, value: action.rawValue)
            + ProtoMessage.blob(field: 2, value: remote)
        return LunaRequest(command: .gimbalControl, body: body, requiresEncryption: false)
    }

    public static func gimbalMove(upDown: Int32, leftRight: Int32) throws -> LunaRequest {
        try gimbalControl(action: .move, upDown: upDown, leftRight: leftRight)
    }

    public static func gimbalRecenterRequest() throws -> LunaRequest {
        try gimbalControl(action: .recenter)
    }

    public static func gimbalFlipRequest() throws -> LunaRequest {
        try gimbalControl(action: .flip)
    }

    public static func gimbalReleaseRequest() throws -> LunaRequest {
        try gimbalControl(action: .move)
    }

    public static let takePictureRequest = LunaRequest(
        command: .takePicture, body: Data(), requiresEncryption: false)

    /// Official-app record start: field 1 = 1 `Capture_MODE_NORMAL`.
    public static let startCaptureRequest = LunaRequest(
        command: .startCapture, body: Data([8, 1]), requiresEncryption: false)

    public static let stopCaptureRequest = LunaRequest(
        command: .stopCapture, body: Data(), requiresEncryption: false)

    public static func setDeviceOptions(types: [UInt32], nested: Data) throws -> LunaRequest {
        guard !types.isEmpty, types.count <= 256, types.allSatisfy({ $0 > 0 && $0 < 1 << 29 }) else {
            throw LunaProtocolError.malformedProtobuf
        }
        var packed = Data()
        for number in types { packed.append(ProtoMessage.varint(UInt64(number))) }
        let body = try ProtoMessage.blob(field: 1, value: packed)
            + ProtoMessage.blob(field: 2, value: nested)
        return LunaRequest(command: .setOptions, body: body, requiresEncryption: false)
    }

    public static func setVideoSubMode(_ mode: LunaVideoSubMode) throws -> LunaRequest {
        return try setDeviceOptions(
            types: [41], nested: try ProtoMessage.integer(field: 41, value: mode.rawValue))
    }

    public static func setColorMode(_ mode: LunaColorMode, functionMode: UInt32 = 7) throws -> LunaRequest {
        return try setPhotographyOptions(
            types: [LunaPhotographyType.colorMode.rawValue],
            nested: try ProtoMessage.integer(field: 35, value: mode.rawValue),
            mode: functionMode)
    }

    /// Integer flag the official schema names COLOR_RECOVERY_SWITCH. Proven no-op
    /// when sent as a varint; kept for GET comparison.
    public static func setColorRecoveryFlag(_ enabled: Bool, functionMode: UInt32 = 7) throws
        -> LunaRequest
    {
        return try setPhotographyOptions(
            types: [LunaPhotographyType.colorRecovery.rawValue],
            nested: try ProtoMessage.integer(field: 73, value: enabled ? 1 : 0),
            mode: functionMode)
    }

    /// Nested `iq_ilog_lut`-shaped payload: enable, lut_type enum, lut_level.
    /// If field 73 is a message, a varint SET is ignored (200 + GET omitted).
    public static func setColorRecoveryNested(
        enable: Bool, lutType: UInt64, lutLevel: UInt64 = 100, functionMode: UInt32 = 7
    ) throws -> LunaRequest {
        var inner = try ProtoMessage.integer(field: 1, value: enable ? 1 : 0)
        inner += try ProtoMessage.integer(field: 2, value: lutType)
        inner += try ProtoMessage.integer(field: 3, value: lutLevel)
        return try setPhotographyOptions(
            types: [LunaPhotographyType.colorRecovery.rawValue],
            nested: try ProtoMessage.blob(field: 73, value: inner),
            mode: functionMode)
    }

    public static func setColorRecoveryNamed(
        enable: Bool, lutType: String, lutLevel: UInt64 = 100, functionMode: UInt32 = 7
    ) throws -> LunaRequest {
        var inner = try ProtoMessage.integer(field: 1, value: enable ? 1 : 0)
        inner += try ProtoMessage.blob(field: 2, value: Data(lutType.utf8))
        inner += try ProtoMessage.integer(field: 3, value: lutLevel)
        return try setPhotographyOptions(
            types: [LunaPhotographyType.colorRecovery.rawValue],
            nested: try ProtoMessage.blob(field: 73, value: inner),
            mode: functionMode)
    }

    public static let getCameraParamsJSONRequest = LunaRequest(
        command: .getCameraParamsJSON, body: Data(), requiresEncryption: false)

    public static func execCmd(_ command: String) throws -> LunaRequest {
        LunaRequest(
            command: .execCmd,
            body: try ProtoMessage.blob(field: 1, value: Data(command.utf8)),
            requiresEncryption: false)
    }

    /// Official-app EV: UI +0.3 → 6. Units are 20 per stop.
    public static func setExposureBias(_ stops: Double, functionMode: UInt32 = 7) throws -> LunaRequest {
        let units = UInt64(clamping: Int((stops * 20).rounded()))
        return try setPhotographyOptions(
            types: [LunaPhotographyType.exposureBias.rawValue],
            nested: try ProtoMessage.integer(field: 7, value: units),
            mode: functionMode)
    }

    public static func setZoomScale(_ factor: Double, functionMode: UInt32 = 7) throws -> LunaRequest {
        guard factor > 0, factor <= 12 else { throw LunaProtocolError.malformedProtobuf }
        return try setPhotographyOptions(
            types: [LunaPhotographyType.zoomScale.rawValue],
            nested: try ProtoMessage.double(field: 53, value: factor),
            mode: functionMode)
    }

    public static func setWhiteBalanceKelvin(_ kelvin: UInt64, functionMode: UInt32 = 7) throws -> LunaRequest {
        guard (2000...10000).contains(kelvin) else { throw LunaProtocolError.malformedProtobuf }
        return try setPhotographyOptions(
            types: [LunaPhotographyType.whiteBalanceKelvin.rawValue],
            nested: try ProtoMessage.integer(field: 39, value: kelvin),
            mode: functionMode)
    }

    public static func setRecordResolution(_ value: UInt64, functionMode: UInt32 = 7) throws -> LunaRequest {
        return try setPhotographyOptions(
            types: [LunaPhotographyType.recordResolution.rawValue, 63],
            nested: try ProtoMessage.integer(field: 31, value: value),
            mode: functionMode)
    }

    public static func setVideoExposure(
        program: LunaExposureProgram, iso: UInt64? = nil, shutterSeconds: Double? = nil,
        functionMode: UInt32 = 7
    ) throws -> LunaRequest {
        var nested = try ProtoMessage.integer(field: 1, value: program.rawValue)
        if let iso { nested += try ProtoMessage.integer(field: 2, value: iso) }
        if let shutterSeconds {
            nested += try ProtoMessage.double(field: 3, value: shutterSeconds)
        }
        return try setPhotographyOptions(
            types: [LunaPhotographyType.videoExposure.rawValue],
            nested: try ProtoMessage.blob(field: 21, value: nested),
            mode: functionMode)
    }

    /// Official-app tap-to-focus: AF_TRIGGER_PARAMS type=1 START + ROI floats.
    public static func setTapFocus(
        x: Double, y: Double, width: Double = 0.15, height: Double = 0.27, functionMode: UInt32 = 7
    ) throws -> LunaRequest {
        let roi = try ProtoMessage.double(field: 1, value: x)
            + (try ProtoMessage.double(field: 2, value: y))
            + (try ProtoMessage.double(field: 3, value: width))
            + (try ProtoMessage.double(field: 4, value: height))
        let params = try ProtoMessage.integer(field: 1, value: 1)
            + (try ProtoMessage.blob(field: 2, value: roi))
        return try setPhotographyOptions(
            types: [LunaPhotographyType.afTrigger.rawValue],
            nested: try ProtoMessage.blob(field: 94, value: params),
            mode: functionMode)
    }

    public static func openTracking(x: Double, y: Double, width: Double, height: Double) throws -> LunaRequest {
        let body = try ProtoMessage.double(field: 1, value: x)
            + (try ProtoMessage.double(field: 2, value: y))
            + (try ProtoMessage.double(field: 3, value: width))
            + (try ProtoMessage.double(field: 4, value: height))
        return LunaRequest(command: .openTracking, body: body, requiresEncryption: false)
    }

    public static let cancelTrackingRequest = LunaRequest(
        command: .cancelTracking, body: Data(), requiresEncryption: false)

    public static func deleteFiles(_ uri: String) throws -> LunaRequest {
        guard !uri.isEmpty, uri.utf8.count <= 512 else { throw LunaProtocolError.malformedProtobuf }
        return LunaRequest(
            command: .deleteFiles,
            body: try ProtoMessage.blob(field: 1, value: Data(uri.utf8)),
            requiresEncryption: false)
    }

    /// Source-backed paging used by public Luna clients: internal storage = 2, page 50.
    public static func fileListRequest(start: UInt32 = 0, count: UInt32 = 50, location: UInt32 = 2)
        throws -> LunaRequest
    {
        let body = try ProtoMessage.integer(field: 1, value: UInt64(location))
            + ProtoMessage.integer(field: 2, value: UInt64(start))
            + ProtoMessage.integer(field: 3, value: UInt64(count))
        return LunaRequest(command: .getFileList, body: body, requiresEncryption: false)
    }

    public static func fileExtraRequest(_ path: String) throws -> LunaRequest {
        guard !path.isEmpty else { throw LunaProtocolError.malformedProtobuf }
        return LunaRequest(
            command: .getFileExtra,
            body: try ProtoMessage.blob(field: 1, value: Data(path.utf8)),
            requiresEncryption: false)
    }

    public static func setAccessCameraFileState(_ state: UInt64) throws -> LunaRequest {
        LunaRequest(
            command: .setAccessCameraFileState,
            body: try ProtoMessage.integer(field: 1, value: state),
            requiresEncryption: false)
    }

    public static func fileListURIs(_ response: Data) throws -> [String] {
        var uris: [String] = []
        func collect(_ message: ProtoMessage) {
            for field in message.fields {
                guard case let .bytes(value) = field.value else { continue }
                if let text = String(data: value, encoding: .utf8), text.contains("/") {
                    uris.append(text)
                } else if let nested = try? ProtoMessage(value) {
                    collect(nested)
                }
            }
        }
        collect(try ProtoMessage(response))
        var seen = Set<String>()
        return uris.filter { seen.insert($0).inserted }
    }

    /// Stick axes are −1…1 in the shared UI; Luna VirtualRC saturates at ±99.
    public static func gimbalStick(pan: Double, tilt: Double) throws -> LunaRequest {
        let leftRight = Int32((min(1, max(-1, pan)) * 99).rounded())
        let upDown = Int32((min(1, max(-1, tilt)) * 99).rounded())
        return try gimbalMove(upDown: upDown, leftRight: leftRight)
    }

    public static func heartbeat(sequence: UInt8) throws -> UCD2Frame {
        try UCD2Frame.plain(type: UCD2Frame.heartbeatType, sequence: sequence)
    }

    public static func encryptionSchemes(response: Data) throws -> [UInt64] {
        let result = try ProtoMessage(response).repeatedUnsigned(1, maximumValues: 32)
        guard !result.isEmpty else { throw LunaProtocolError.missingField(1) }
        return result
    }

    /// Validates the protocol success enum and X9.63 encoding. Platform P-256
    /// construction MUST additionally validate that this is a point on the curve.
    public static func cameraPublicKey(response: Data) throws -> Data {
        let message = try ProtoMessage(response)
        let result = try message.unsigned(1, default: 0)
        guard result == 1 else { throw LunaProtocolError.keyExchangeRejected(result) }
        let key = try message.bytes(2)
        try validatePublicKeyEncoding(key)
        return key
    }

    private static func validatePublicKeyEncoding(_ publicKey: Data) throws {
        guard publicKey.count == 65, publicKey.first == 4,
              publicKey.dropFirst().contains(where: { $0 != 0 }) else {
            throw LunaProtocolError.invalidPublicKey
        }
    }

    public static func deviceInformation(response: Data) throws -> LunaDeviceInformation {
        let options = try responseOptions(response)
        let reportedModel = try options.string(48)
        guard reportedModel == model else { throw LunaProtocolError.unexpectedModel }
        let firmware = try options.string(30)
        guard !firmware.isEmpty, firmware.utf8.count <= 128 else { throw LunaProtocolError.invalidField(30) }
        let serial: String?
        if let encoded = try options.optionalBytes(15) {
            guard let value = String(data: encoded, encoding: .utf8), !value.isEmpty, encoded.count <= 128 else {
                throw LunaProtocolError.invalidField(15)
            }
            serial = value
        } else { serial = nil }
        return LunaDeviceInformation(model: reportedModel, firmware: firmware, serial: serial)
    }

    public static func authorizationStatus(response: Data) throws -> LunaAuthorizationStatus {
        let value = try ProtoMessage(response).unsigned(1, default: 0)
        guard let result = LunaAuthorizationStatus(rawValue: value) else {
            throw LunaProtocolError.unsupportedAuthorizationStatus(value)
        }
        return result
    }

    /// Call after the successful response to request 86, for async notification
    /// 8209 (observed) or 8228 (source-backed fallback). Zero is proto3's default.
    public static func validateAuthorizationNotification(_ message: UCD2Message) throws {
        guard message.code == 8209 || message.code == 8228, message.contentType == 2,
              message.reserved == 0 else { throw LunaProtocolError.unexpectedResponse }
        let body = try ProtoMessage(message.body)
        let result = try body.unsigned(1, default: 0)
        let operation = try body.unsigned(2, default: 0)
        guard operation == 0 || operation == 1 else {
            throw LunaProtocolError.unexpectedAuthorizationOperation(operation)
        }
        guard result == 0 else { throw LunaProtocolError.authorizationRejected(result) }
    }

    /// Only pass a body whose outer response was authenticated for an encrypted
    /// credential request. A plaintext response must never satisfy that request.
    public static func wifiCredentials(response: Data) throws -> LunaWiFiCredentials {
        let options = try responseOptions(response)
        let wifi = try ProtoMessage(options.bytes(36), maximumBytes: 1_024)
        let ssidBytes = try wifi.bytes(1)
        let passwordBytes = try wifi.bytes(2)
        guard (1...32).contains(ssidBytes.count), !ssidBytes.contains(0),
              let ssid = String(data: ssidBytes, encoding: .utf8) else {
            throw LunaProtocolError.invalidField(1)
        }
        guard (8...64).contains(passwordBytes.count), !passwordBytes.contains(0),
              let password = String(data: passwordBytes, encoding: .utf8) else {
            throw LunaProtocolError.invalidField(2)
        }
        return LunaWiFiCredentials(ssid: ssid, password: password)
    }

    private static func responseOptions(_ data: Data) throws -> ProtoMessage {
        let response = try ProtoMessage(data)
        // GetOptionsResp field 1 contains returned option IDs, NOT an error
        // status. Command success/failure belongs to the outer 200/500 message.
        _ = try response.repeatedUnsigned(1, maximumValues: 256)
        return try ProtoMessage(response.bytes(2))
    }
}

/// The eight-byte little-endian counter is observed to advance by 40 per video
/// packet at 25 fps. Its epoch/timebase is not proven; keep the original value.
public struct LunaMediaPacket: Equatable, Sendable {
    public let subtype: UInt8
    public let timestamp: UInt64
    public let bytes: Data
    public var hevcAnnexB: Data? { subtype == 0x20 ? bytes : nil }

    public init(frame: UCD2Frame) throws {
        guard frame.type == UCD2Frame.mediaType, frame.isPlain else {
            throw LunaProtocolError.malformedMedia
        }
        let payload = frame.payload
        guard payload.count >= 9 else { throw LunaProtocolError.malformedMedia }
        subtype = payload.byte(at: 0)
        timestamp = payload.littleEndian(at: 1)
        bytes = payload.bytes(in: 9..<payload.count)
        guard subtype != 0x20 || !bytes.isEmpty else { throw LunaProtocolError.malformedMedia }
    }
}

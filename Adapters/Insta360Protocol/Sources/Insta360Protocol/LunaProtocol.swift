import Foundation

/// The verified read/authorization/live command subset; camera settings and
/// recording are intentionally absent until independently established.
public enum LunaCommand: UInt16, Sendable {
    case startLive = 1
    case stopLive = 2
    case getOptions = 8
    case captureStatus = 15
    case checkAuthorization = 39
    case requestAuthorization = 86
    case encryptionCapabilities = 240
    case keyExchange = 241
}

public struct LunaRequest: Equatable, Sendable {
    public let command: LunaCommand
    public let body: Data
    public let requiresEncryption: Bool

    public func message(identifier: UInt32) throws -> UCD2Message {
        guard identifier != 0 else { throw LunaProtocolError.invalidIdentifier }
        return try UCD2Message(code: command.rawValue, identifier: identifier, body: body,
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

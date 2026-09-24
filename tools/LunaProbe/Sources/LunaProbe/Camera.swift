import Foundation
import Insta360Protocol
import Network

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

func unhex(_ text: String) throws -> Data {
    let clean = text.filter { !$0.isWhitespace }
    guard clean.count % 2 == 0 else { throw ProbeError("odd hex length") }
    var result = Data()
    var index = clean.startIndex
    while index < clean.endIndex {
        let next = clean.index(index, offsetBy: 2)
        guard let byte = UInt8(clean[index..<next], radix: 16) else { throw ProbeError("bad hex") }
        result.append(byte)
        index = next
    }
    return result
}

let startTime = Date()
func stamp() -> String { String(format: "%7.3f", Date().timeIntervalSince(startTime)) }
func log(_ text: String) { print("[\(stamp())] \(text)") }

/// One phone-protocol TCP session. All mutable state lives on `queue`; public
/// calls block the caller (this is a CLI, not an app).
final class Camera {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "luna.probe")
    private var reassembler = try! UCD2Reassembler()
    private var counter = LunaRequestCounter()
    private var pending: [UInt32: (UCD2Message) -> Void] = [:]
    private var greeted = false
    private let greeting = DispatchSemaphore(value: 0)
    private var heartbeat: DispatchSourceTimer?
    private(set) var failure: Error?
    var onNotification: (UCD2Message) -> Void = printNotification
    var onMedia: ((LunaMediaPacket) -> Void)?
    var quietHeartbeats = true
    private(set) var info: LunaDeviceInformation?

    init(host: String = LunaProtocol.defaultHost, port: UInt16 = LunaProtocol.defaultPort) {
        let parameters = NWParameters.tcp
        // Pin to Wi-Fi so a wired default route never carries camera traffic.
        if ProcessInfo.processInfo.environment["LUNA_ANY_INTERFACE"] == nil { parameters.requiredInterfaceType = .wifi }
        connection = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: parameters)
    }

    /// Connect, preface, greeting, heartbeats, device info and authorization check.
    func open(identity: UUID) throws {
        let ready = DispatchSemaphore(value: 0)
        var state: NWConnection.State = .setup
        connection.stateUpdateHandler = { newState in
            state = newState; if ProcessInfo.processInfo.environment["LUNA_DEBUG"] != nil { log("state \(newState)") }
            switch newState {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        connection.start(queue: queue)
        guard ready.wait(timeout: .now() + 6) == .success, case .ready = state else {
            connection.cancel()
            throw ProbeError("TCP connect failed: \(state)")
        }
        receive()
        try write(LunaProtocol.tcpPreface)
        guard greeting.wait(timeout: .now() + 8) == .success, failure == nil else {
            throw ProbeError("no type-5 greeting \(failure.map { "\($0)" } ?? "")")
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self, let frame = try? LunaProtocol.heartbeat(sequence: self.counter.nextSequence()) else { return }
            self.connection.send(content: frame.raw, completion: .idempotent)
        }
        timer.resume()
        heartbeat = timer
        let device = try LunaProtocol.deviceInformation(
            response: request(LunaProtocol.deviceInformationRequest(includeSerial: true)))
        info = device
        let auth = try LunaProtocol.authorizationStatus(response: request(LunaProtocol.authorizationCheck(identity: identity)))
        guard auth == .authorized else { throw ProbeError("identity not authorized: \(auth)") }
    }

    func close() {
        heartbeat?.cancel()
        connection.cancel()
    }

    private func write(_ data: Data) throws {
        var error: Error?
        let done = DispatchSemaphore(value: 0)
        connection.send(content: data, completion: .contentProcessed { error = $0; done.signal() })
        guard done.wait(timeout: .now() + 8) == .success else { throw ProbeError("send timeout") }
        if let error { throw error }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [self] data, _, complete, error in
            if let data, !data.isEmpty { handle(data) }
            if let error { fail(error); return }
            if complete { fail(ProbeError("camera closed TCP")); return }
            receive()
        }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        log("SESSION FAILURE: \(error)")
        if !greeted { greeting.signal() }
        let waiting = pending
        pending = [:]
        for (_, callback) in waiting {
            callback(try! UCD2Message(code: 0, identifier: 0))
        }
    }

    private func handle(_ data: Data) {
        for frame in reassembler.feed(data) {
            switch frame.type {
            case UCD2Frame.heartbeatType:
                if !greeted { greeted = true; greeting.signal() }
            case UCD2Frame.mediaType:
                if let packet = try? LunaMediaPacket(frame: frame) { onMedia?(packet) }
            case UCD2Frame.messageType:
                guard let message = try? frame.plainMessage() else {
                    log("undecodable/encrypted message frame, \(frame.raw.count) bytes")
                    continue
                }
                if message.code == 200 || message.code == 500, let callback = pending.removeValue(forKey: message.identifier) {
                    callback(message)
                } else {
                    onNotification(message)
                }
            default:
                log("frame type \(frame.type) (\(frame.payloadLength) bytes)")
            }
        }
    }

    /// Sends one request; returns the raw reply message (200 or 500).
    func send(_ request: LunaRequest, timeout: TimeInterval = 8) throws -> UCD2Message {
        if let failure { throw failure }
        let done = DispatchSemaphore(value: 0)
        var reply: UCD2Message?
        var identifier: UInt32 = 0
        var frame: UCD2Frame?
        try queue.sync {
            identifier = counter.nextIdentifier()
            frame = try request.plainFrame(identifier: identifier, sequence: counter.nextSequence())
            pending[identifier] = { reply = $0; done.signal() }
        }
        try write(frame!.raw)
        guard done.wait(timeout: .now() + timeout) == .success else {
            queue.sync { _ = pending.removeValue(forKey: identifier) }
            throw ProbeError("timeout waiting for reply to cmd \(request.wireCode)")
        }
        if let failure { throw failure }
        return reply!
    }

    /// Sends and requires 200; returns the body.
    func request(_ request: LunaRequest, timeout: TimeInterval = 8) throws -> Data {
        let reply = try send(request, timeout: timeout)
        guard reply.code == 200 else {
            throw ProbeError("cmd \(request.wireCode) rejected with \(reply.code) body \(hex(reply.body))")
        }
        return reply.body
    }
}

func printNotification(_ message: UCD2Message) {
    let decoded = (try? LunaNotification(message: message)).map(describe) ?? "undecodable"
    log("NOTIFY \(message.code) \(decoded) raw=\(hex(message.body))")
}

// MARK: Printing

/// Compact field=value rendering of the package's decoded structs; nil and
/// empty values are skipped so only reported fields show.
func describe(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .optional:
        return mirror.children.first.map { describe($0.value) } ?? "nil"
    case .collection, .set:
        return "[" + mirror.children.map { describe($0.value) }.joined(separator: ", ") + "]"
    case .struct, .class, .enum, .tuple:
        if let data = value as? Data { return "\(data.count)b" }
        if mirror.children.isEmpty { return "\(value)" }
        var parts: [String] = []
        for child in mirror.children {
            let inner = Mirror(reflecting: child.value)
            if inner.displayStyle == .optional, inner.children.isEmpty { continue }
            if inner.displayStyle == .collection, inner.children.isEmpty { continue }
            let text = describe(child.value)
            parts.append(child.label.map { "\($0)=\(text)" } ?? text)
        }
        let name = mirror.displayStyle == .enum ? "\(value)".prefix { $0 != "(" } : ""
        return "\(name){" + parts.joined(separator: " ") + "}"
    default:
        return "\(value)"
    }
}

/// Generic protobuf dump so fields the typed decoders ignore stay visible.
func dump(_ data: Data, depth: Int = 0) -> String {
    guard !data.isEmpty else { return "{}" }
    guard depth < 6, let message = try? ProtoMessage(data) else { return "0x" + hex(data) }
    return "{" + message.fields.map { field -> String in
        switch field.value {
        case .unsigned(let value): return "\(field.number)=\(value)"
        case .fixed64(let bytes):
            var raw: UInt64 = 0
            _ = withUnsafeMutableBytes(of: &raw) { bytes.copyBytes(to: $0) }
            return "\(field.number)=\(Double(bitPattern: raw))d"
        case .fixed32(let bytes):
            var raw: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &raw) { bytes.copyBytes(to: $0) }
            return "\(field.number)=\(Float(bitPattern: raw))f"
        case .bytes(let bytes):
            if let text = String(data: bytes, encoding: .utf8), !text.isEmpty,
               text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) {
                return "\(field.number)=\"\(text)\""
            }
            return "\(field.number)=" + dump(bytes, depth: depth + 1)
        }
    }.joined(separator: " ") + "}"
}

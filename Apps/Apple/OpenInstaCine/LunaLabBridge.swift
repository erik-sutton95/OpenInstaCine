#if DEBUG
import Darwin
import Foundation
import Insta360Apple
import Network

/// DEBUG USB lab: Mac talks HTTP/TCP to the phone; phone talks to the camera AP.
/// Port 18776 is JSON commands. Port 18778 is a length-prefixed UDP pipe to :6000.
final class LunaLabBridgeServer {
    static let httpPort: UInt16 = 18_776
    static let udpPort: UInt16 = 18_778

    private let backend: LunaCameraBackend
    private let queue = DispatchQueue(label: "luna.lab.bridge")
    private var httpListener: NWListener?
    private var udpListener: NWListener?
    private var httpConnections: [ObjectIdentifier: NWConnection] = [:]
    private var udpClient: NWConnection?
    private var udpCamera: NWConnection?
    private var udpBuffer = Data()
    private var notes: [[String: String]] = []
    private var lastError: String?

    init(backend: LunaCameraBackend) {
        self.backend = backend
    }

    func start() throws {
        let http = NWParameters.tcp
        http.allowLocalEndpointReuse = true
        let httpListener = try NWListener(using: http, on: NWEndpoint.Port(rawValue: Self.httpPort)!)
        httpListener.newConnectionHandler = { [weak self] connection in self?.acceptHTTP(connection) }
        httpListener.start(queue: queue)
        self.httpListener = httpListener

        let udp = NWParameters.tcp
        udp.allowLocalEndpointReuse = true
        let udpListener = try NWListener(using: udp, on: NWEndpoint.Port(rawValue: Self.udpPort)!)
        udpListener.newConnectionHandler = { [weak self] connection in self?.acceptUDPPipe(connection) }
        udpListener.start(queue: queue)
        self.udpListener = udpListener
        note("listeners \(Self.httpPort)/\(Self.udpPort)")
    }

    func note(_ message: String) {
        queue.async { [weak self] in
            self?.notes.append(["utc": Self.now(), "note": message])
        }
    }

    func fail(_ message: String) {
        queue.async { [weak self] in
            self?.lastError = message
            self?.notes.append(["utc": Self.now(), "error": message])
        }
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func acceptHTTP(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        httpConnections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.dropHTTP(id) }
            if case .cancelled = state { self?.dropHTTP(id) }
        }
        connection.start(queue: queue)
        readHTTP(connection, id: id)
    }

    private func dropHTTP(_ id: ObjectIdentifier) {
        httpConnections[id]?.cancel()
        httpConnections[id] = nil
    }

    private func readHTTP(_ connection: NWConnection, id: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handleHTTP(data, on: connection)
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readHTTP(connection, id: id)
        }
    }

    private func handleHTTP(_ data: Data, on connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8) else {
            reply(connection, status: 400, body: #"{"ok":false,"error":"not utf8"}"#)
            return
        }
        let parts = text.split(separator: "\r\n\r\n", maxSplits: 1, omittingEmptySubsequences: false)
        let header = String(parts.first ?? "")
        let body = parts.count > 1 ? String(parts[1]) : ""
        let first = header.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let tokens = first.split(separator: " ")
        let method = tokens.first.map(String.init) ?? ""
        let path = tokens.dropFirst().first.map(String.init) ?? "/"
        let payload = performAsync { [backend] in
            await self.dispatch(method: method, path: path, body: body, backend: backend)
        }
        replyJSON(connection, payload)
    }

    @MainActor
    private func dispatch(method: String, path: String, body: String, backend: LunaCameraBackend) async -> [String: Any] {
        do {
            if method == "GET" && path.hasPrefix("/health") {
                return health(backend)
            }
            if method == "GET" && path.hasPrefix("/log") {
                return ["ok": true, "log": notes, "error": lastError as Any]
            }
            if method == "POST" && path == "/photo/get" {
                let cmd = json(body)
                let types = uint32List(cmd["types"]) ?? [35, 72, 73]
                let mode = uint32(cmd["mode"]) ?? 7
                let values = try await backend.labGetPhotography(types: types, mode: mode)
                note("GET photo types=\(types) mode=\(mode)")
                return ["ok": true, "values": stringify(values)]
            }
            if method == "POST" && path == "/photo/set" {
                let cmd = json(body)
                guard let field = uint32(cmd["field"]), let value = uint64(cmd["value"]) else {
                    return ["ok": false, "error": "field and value required"]
                }
                let mode = uint32(cmd["mode"]) ?? 7
                let reply = try await backend.labSetPhotography(field: field, value: value, mode: mode)
                let after = try await backend.labGetPhotography(types: [field, 35, 72, 73], mode: mode)
                note("SET photo \(field)=\(value) mode=\(mode)")
                return [
                    "ok": true,
                    "set_hex": reply.map { String(format: "%02x", $0) }.joined(),
                    "after": stringify(after),
                ]
            }
            if method == "POST" && path == "/command" {
                let cmd = json(body)
                guard let code = uint16(cmd["code"]) else {
                    return ["ok": false, "error": "code required"]
                }
                let payload = try hexData((cmd["body"] as? String) ?? "")
                let reply = try await backend.labCommand(code: code, body: payload)
                note("cmd \(code) body=\(payload.count)B")
                return [
                    "ok": true,
                    "reply_hex": reply.map { String(format: "%02x", $0) }.joined(),
                ]
            }
            if method == "POST" && path == "/set73" {
                let report = try await backend.labSet73Experiment()
                note("SET 73 experiment")
                return ["ok": true, "report": report]
            }
            return ["ok": false, "error": "not found"]
        } catch {
            fail(String(describing: error))
            return ["ok": false, "error": String(describing: error)]
        }
    }

    @MainActor
    private func health(_ backend: LunaCameraBackend) -> [String: Any] {
        [
            "ok": true,
            "ready": backend.labReady,
            "wifi": backend.labWifiAddress as Any,
            "error": lastError as Any,
            "udp_pipe": udpClient != nil,
            "udp_camera": udpCamera != nil,
        ]
    }

    private func performAsync(_ work: @escaping @MainActor () async -> [String: Any]) -> [String: Any] {
        let box = ResultBox()
        let lock = DispatchSemaphore(value: 0)
        Task { @MainActor in
            box.value = await work()
            lock.signal()
        }
        _ = lock.wait(timeout: .now() + 25)
        return box.value ?? ["ok": false, "error": "lab command timed out"]
    }

    private func acceptUDPPipe(_ connection: NWConnection) {
        if let existing = udpClient {
            existing.cancel()
        }
        udpClient = connection
        udpBuffer.removeAll()
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.dropUDPPipe() }
            if case .cancelled = state { self?.dropUDPPipe() }
            if case .ready = state { self?.ensureCameraUDP() }
        }
        connection.start(queue: queue)
        receivePipe(connection)
        note("udp pipe client")
    }

    private func dropUDPPipe() {
        udpClient?.cancel()
        udpClient = nil
        udpCamera?.cancel()
        udpCamera = nil
        udpBuffer.removeAll()
    }

    private func ensureCameraUDP() {
        if udpCamera != nil { return }
        guard let local = LunaWiFiAddress.current() else {
            note("udp camera wait: no 192.168.42 address")
            return
        }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .init(local), port: .any)
        let camera = NWConnection(host: "192.168.42.1", port: 6000, using: params)
        camera.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.note("udp camera failed \(error)")
            }
        }
        camera.start(queue: queue)
        udpCamera = camera
        receiveCamera(camera)
        note("udp camera from \(local)")
    }

    private func receivePipe(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.udpBuffer.append(data)
                self.drainPipe()
            }
            if isComplete || error != nil {
                if self.udpClient === connection { self.dropUDPPipe() }
                return
            }
            self.receivePipe(connection)
        }
    }

    private func drainPipe() {
        ensureCameraUDP()
        while udpBuffer.count >= 4 {
            let size = Int(
                UInt32(udpBuffer[udpBuffer.startIndex]) << 24
                    | UInt32(udpBuffer[udpBuffer.startIndex + 1]) << 16
                    | UInt32(udpBuffer[udpBuffer.startIndex + 2]) << 8
                    | UInt32(udpBuffer[udpBuffer.startIndex + 3]))
            guard size <= 65_535 else {
                note("udp pipe oversize \(size)")
                dropUDPPipe()
                return
            }
            if udpBuffer.count < 4 + size { return }
            let payload = udpBuffer.subdata(in: 4..<(4 + size))
            udpBuffer.removeSubrange(0..<(4 + size))
            udpCamera?.send(content: payload, completion: .contentProcessed { _ in })
        }
    }

    private func receiveCamera(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty, let client = self.udpClient {
                var frame = Data()
                let size = UInt32(data.count).bigEndian
                withUnsafeBytes(of: size) { frame.append(contentsOf: $0) }
                frame.append(data)
                client.send(content: frame, completion: .contentProcessed { _ in })
            }
            if error == nil, self.udpCamera === connection {
                self.receiveCamera(connection)
            }
        }
    }

    private func json(_ body: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
    }

    private func stringify(_ values: [Int: UInt64]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values.map { ("\($0.key)", "\($0.value)") })
    }

    private func uint16(_ value: Any?) -> UInt16? {
        uint64(value).flatMap { $0 <= UInt64(UInt16.max) ? UInt16($0) : nil }
    }

    private func uint32(_ value: Any?) -> UInt32? {
        uint64(value).flatMap { $0 <= UInt64(UInt32.max) ? UInt32($0) : nil }
    }

    private func uint32List(_ value: Any?) -> [UInt32]? {
        guard let items = value as? [Any] else { return nil }
        let mapped = items.compactMap(uint32)
        return mapped.count == items.count ? mapped : nil
    }

    private func uint64(_ value: Any?) -> UInt64? {
        if let n = value as? UInt64 { return n }
        if let n = value as? Int, n >= 0 { return UInt64(n) }
        if let n = value as? Double, n >= 0, n == n.rounded() { return UInt64(n) }
        if let n = value as? NSNumber { return n.uint64Value }
        if let s = value as? String { return UInt64(s) }
        return nil
    }

    private func hexData(_ text: String) throws -> Data {
        let clean = text.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { throw LabHexError.odd }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { throw LabHexError.bad }
            data.append(byte)
            index = next
        }
        return data
    }

    private func replyJSON(_ connection: NWConnection, _ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]))
            ?? Data(#"{"ok":false}"#.utf8)
        reply(connection, status: 200, body: String(data: data, encoding: .utf8) ?? "{}")
    }

    private func reply(_ connection: NWConnection, status: Int, body: String) {
        let payload = Data(body.utf8)
        let header =
            "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private enum LabHexError: Error { case odd, bad }

private final class ResultBox: @unchecked Sendable {
    var value: [String: Any]?
}

enum LunaWiFiAddress {
    static func current() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(first) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0,
                NI_NUMERICHOST) == 0
            {
                let text = String(cString: buffer)
                if text.hasPrefix("192.168.42."), text != "192.168.42.1" { return text }
            }
        }
        return nil
    }
}
#endif

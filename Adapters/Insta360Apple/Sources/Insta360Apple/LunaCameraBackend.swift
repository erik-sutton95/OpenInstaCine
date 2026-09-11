import CryptoKit
import Foundation
import Insta360Protocol
import MonitorContracts

/// Insta360 camera adapter. Only the experimentally verified Luna live-video path is enabled.
/// BLE performs consent and encrypted credential bootstrap; TCP carries UCD2 video.
@MainActor
public final class LunaCameraBackend: CameraBackend {
    public let capabilities: CameraCapabilities = [.liveVideo]
    public var eventHandler: ((CameraBackendEvent) -> Void)?
    public var isOnCameraNetwork: Bool { LunaWiFi.localAddress != nil }
    private let bluetooth = LunaBluetooth()
    private let tcp = LunaTCPTransport()
    private let existingNetwork: Bool
    private let identityOverride: UUID?
    private var identity: UUID?
    private var selected: MonitorCamera?
    private var credentials: LunaStoredWiFi?
    private var sessionKey: SymmetricKey?
    private var bleParser = try! UCD2Reassembler(maximumFrameSize: 1024 * 1024)
    private var tcpParser = try! UCD2Reassembler()
    private var counter = LunaRequestCounter()
    private var heartbeat: Task<Void, Never>?
    private var generation = 0
    private var isTCP = false
    private var streaming = false
    private var liveStartAttempted = false
    private var handshakeComplete = false
    private var greetingOperation: UUID?
    private var authorizationOperation: UUID?
    private var bleHasNotification = false
    private var tcpGreetingSeen = false
    private var tcpGreetingWaiter: CheckedContinuation<Void, Error>?
    private var tcpGreetingTimeout: Task<Void, Never>?
    private var approval: UCD2Message?
    private var receivedNonces = Set<Data>()
    private struct Pending {
        let generation: Int
        let operation: UUID
        let continuation: CheckedContinuation<Data, Error>
        let encrypted: Bool
        var writeCompleted = false
        var responseBody: Data?
        let timeout: Task<Void, Never>
    }
    private var pending: [UInt32: Pending] = [:]
    private var approvalWaiter: CheckedContinuation<Void, Error>?
    private var approvalTimeout: Task<Void, Never>?

    /// Existing-network mode supports a Mac/Simulator already associated to the camera AP.
    /// Identity injection is for an already owner-approved installation, never a captured app identity.
    public init(useExistingNetwork: Bool = false, authorizedIdentity: UUID? = nil) {
        existingNetwork = useExistingNetwork
        identityOverride = authorizedIdentity
        bluetooth.onCamera = { [weak self] in self?.eventHandler?(.discovered($0)) }
        bluetooth.onData = { [weak self] in self?.receive($0, fromTCP: false) }
        bluetooth.onDisconnect = { [weak self] reason in self?.transportDropped(reason) }
        tcp.onData = { [weak self] in self?.receive($0, fromTCP: true) }
        tcp.onDisconnect = { [weak self] reason in self?.transportDropped(reason) }
    }
    public func startScan() async throws {
        try Task.checkCancellation()
        eventHandler?(.phase(.scanning))
        if existingNetwork {
            guard isOnCameraNetwork else {
                throw CameraBackendError.unavailable(
                    "Join the Luna camera Wi-Fi on this Mac before opening the feed.")
            }
            let camera = MonitorCamera(
                id: UUID(uuidString: "B5BB58F0-02EC-4DBD-AC83-70329F77C144")!,
                name: "Luna Ultra · current Wi-Fi", model: LunaProtocol.model,
                capabilities: capabilities)
            eventHandler?(.discovered(camera))
            return
        }
        try await bluetooth.startScan()
    }
    public func connect(to camera: MonitorCamera) async throws {
        try Task.checkCancellation()
        disconnect()
        generation += 1
        let token = generation
        selected = camera
        identity = try identityOverride ?? LunaSecureStore.identity()
        guard let identity else {
            throw CameraBackendError.unavailable(
                "A camera authorization identity could not be created.")
        }
        var expectedSerial: String?
        do {
            if !existingNetwork {
                eventHandler?(.phase(.connecting))
                try await bluetooth.connect(id: camera.id)
                try validate(token)
                let greetingDeadline = Date().addingTimeInterval(5)
                while !bleHasNotification, Date() < greetingDeadline {
                    try validate(token)
                    try await Task.sleep(for: .milliseconds(50))
                }
                // The verified client proceeds with GetOptions after this bounded
                // notification grace, even when the camera omits its initial greeting.
                try validate(token)
                eventHandler?(.phase(.negotiating))
                let info = try LunaProtocol.deviceInformation(
                    response: await request(
                        LunaProtocol.deviceInformationRequest(includeSerial: true)))
                // BE80 is shared by more cameras. Do not apply a Luna preview profile to an unverified model.
                guard info.model == LunaProtocol.model else {
                    throw CameraBackendError.unavailable(
                        "This camera is \(info.model). This build currently supports the verified Luna Ultra connection profile."
                    )
                }
                guard let serial = info.serial, !serial.isEmpty else {
                    throw CameraBackendError.unavailable(
                        "The camera did not provide an identity to verify its Wi-Fi handoff.")
                }
                expectedSerial = serial
                eventHandler?(
                    .information(
                        CameraInformation(
                            model: info.model, firmware: info.firmware, previewTransfer: .rec709)))
                let schemes = try LunaProtocol.encryptionSchemes(
                    response: await request(LunaProtocol.encryptionCapabilitiesRequest))
                guard schemes.contains(3) else {
                    throw CameraBackendError.unavailable(
                        "The camera does not support the verified encrypted connection handshake.")
                }
                let privateKey = P256.KeyAgreement.PrivateKey()
                let exchange = try LunaProtocol.keyExchangeRequest(
                    publicKey: privateKey.publicKey.x963Representation)
                let cameraKey = try LunaProtocol.cameraPublicKey(response: await request(exchange))
                let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: cameraKey)
                let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
                sessionKey = secret.hkdfDerivedSymmetricKey(
                    using: SHA256.self, salt: LunaProtocol.hkdfSalt,
                    sharedInfo: LunaProtocol.hkdfInfo,
                    outputByteCount: LunaProtocol.sessionKeyByteCount)
                let authenticatedInfo = try LunaProtocol.deviceInformation(
                    response: await request(LunaProtocol.deviceInformationRequest(encrypted: true)))
                guard authenticatedInfo.model == info.model else {
                    throw CameraBackendError.unavailable(
                        "The encrypted camera identity did not match the selected device.")
                }
                let authorization = try LunaProtocol.authorizationStatus(
                    response: await request(LunaProtocol.authorizationCheck(identity: identity)))
                if authorization == .approvalRequired {
                    eventHandler?(.phase(.awaitingApproval))
                    approval = nil
                    authorizationOperation = UUID()
                    _ = try await request(LunaProtocol.requestAuthorization)
                    try await waitForApproval()
                } else if authorization != .authorized {
                    throw CameraBackendError.unavailable(
                        "The camera is in use by another connection. Close Insta360 on the other device, then reconnect."
                    )
                }
                eventHandler?(.phase(.readingWiFi))
                let wifi = try LunaProtocol.wifiCredentials(
                    response: await request(LunaProtocol.wifiCredentialsRequest))
                let saved = LunaStoredWiFi(ssid: wifi.ssid, password: wifi.password)
                try LunaSecureStore.save(saved, cameraID: camera.id)
                credentials = saved
                bluetooth.disconnect()
                sessionKey = nil
                receivedNonces.removeAll()
                try validate(token)
                eventHandler?(.phase(.joiningWiFi))
                try await LunaWiFi.join(saved)
                eventHandler?(.joinedWiFi(ssid: saved.ssid))
            }
            try validate(token)
            eventHandler?(.phase(.openingVideo))
            isTCP = true
            counter = LunaRequestCounter()
            try await tcp.connect(
                host: LunaProtocol.defaultHost, port: LunaProtocol.defaultPort,
                localAddress: LunaWiFi.localAddress)
            try await tcp.send(LunaProtocol.tcpPreface)
            try await waitForTCPGreeting()
            try validate(token)
            startHeartbeat(token: token)
            let info = try LunaProtocol.deviceInformation(
                response: await request(LunaProtocol.deviceInformationRequest(includeSerial: true)))
            guard info.model == LunaProtocol.model else {
                throw CameraBackendError.unavailable(
                    "The Wi-Fi device is not a supported Luna camera.")
            }
            if !existingNetwork, info.serial != expectedSerial {
                throw CameraBackendError.unavailable(
                    "The Wi-Fi connection reached a different camera. Join the selected camera's network and retry."
                )
            }
            eventHandler?(
                .information(
                    CameraInformation(
                        model: info.model, firmware: info.firmware, previewTransfer: .rec709)))
            let authorization = try LunaProtocol.authorizationStatus(
                response: await request(LunaProtocol.authorizationCheck(identity: identity)))
            guard authorization == .authorized else {
                throw CameraBackendError.unavailable(
                    "This installation has not been approved by the camera. Connect over Bluetooth and accept the prompt on the camera."
                )
            }
            _ = try await request(LunaProtocol.captureStatusRequest)
            liveStartAttempted = true
            _ = try await request(LunaProtocol.startLiveRequest)
            try validate(token)
            streaming = true
            handshakeComplete = true
            eventHandler?(.phase(.streaming))
        } catch {
            if token == generation { disconnect() }
            throw error
        }
    }
    public func disconnect() {
        generation += 1
        handshakeComplete = false
        heartbeat?.cancel()
        heartbeat = nil
        if liveStartAttempted,
            let frame = try? LunaProtocol.stopLiveRequest.plainFrame(
                identifier: counter.nextIdentifier(), sequence: counter.nextSequence())
        {
            tcp.sendBeforeClosing(frame.raw)
        } else {
            tcp.disconnect()
        }
        streaming = false
        liveStartAttempted = false
        isTCP = false
        tcpGreetingSeen = false
        bleHasNotification = false
        bluetooth.disconnect()
        sessionKey = nil
        receivedNonces.removeAll()
        bleParser = try! UCD2Reassembler(maximumFrameSize: 1024 * 1024)
        tcpParser = try! UCD2Reassembler()
        failPending(CancellationError())
        counter = LunaRequestCounter()
        approval = nil
        eventHandler?(.phase(.idle))
    }
    public func forget(cameraID: UUID) {
        LunaSecureStore.forget(cameraID: cameraID)
        if selected?.id == cameraID { credentials = nil }
    }
    public func leaveCameraNetwork() {
        disconnect()
        if let credentials { LunaWiFi.leave(ssid: credentials.ssid) }
    }
    public func rejoinCameraNetwork() async throws {
        let token = generation
        guard let selected else { return }
        if let credentials { try await LunaWiFi.join(credentials) }
        try validate(token)
        try await connect(to: selected)
    }
    private func validate(_ token: Int) throws {
        try Task.checkCancellation()
        guard token == generation else { throw CancellationError() }
    }
    private func request(_ request: LunaRequest) async throws -> Data {
        let requestGeneration = generation
        let operation = UUID()
        let id = counter.nextIdentifier()
        let sequence = counter.nextSequence()
        let frame: UCD2Frame
        if request.requiresEncryption {
            guard let key = sessionKey else {
                throw CameraBackendError.unavailable(
                    "The encrypted camera session is not established.")
            }
            let payload = try request.message(identifier: id).payload
            let aad = try UCD2Frame.scheme3AssociatedData(
                sequence: sequence, plaintextLength: payload.count)
            let box = try AES.GCM.seal(payload, using: key, authenticating: aad)
            frame = try UCD2Frame.scheme3(
                sequence: sequence, ciphertext: box.ciphertext, nonce: Data(box.nonce), tag: box.tag
            )
        } else {
            frame = try request.plainFrame(identifier: id, sequence: sequence)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in
                let timer = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled, let self,
                        let pending = self.takePending(
                            id, generation: requestGeneration, operation: operation)
                    else { return }
                    pending.continuation.resume(
                        throwing: CameraBackendError.unavailable(
                            "The camera did not answer connection command \(request.command.rawValue). Reconnect and try again."
                        ))
                }
                pending[id] = Pending(
                    generation: requestGeneration, operation: operation, continuation: continuation,
                    encrypted: request.requiresEncryption, timeout: timer)
                Task { [weak self] in
                    guard let self, requestGeneration == self.generation, self.pending[id] != nil
                    else { return }
                    do {
                        if self.isTCP {
                            try await self.tcp.send(frame.raw)
                        } else {
                            try await self.bluetooth.write(frame.raw)
                        }
                        if var entry = self.pending[id], entry.generation == requestGeneration,
                            entry.operation == operation
                        {
                            entry.writeCompleted = true
                            self.pending[id] = entry
                            self.finishPendingIfComplete(
                                id, generation: requestGeneration, operation: operation)
                        }
                    } catch {
                        if let entry = self.takePending(
                            id, generation: requestGeneration, operation: operation)
                        {
                            entry.timeout.cancel()
                            entry.continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if let entry = self?.takePending(
                    id, generation: requestGeneration, operation: operation)
                {
                    entry.timeout.cancel()
                    entry.continuation.resume(throwing: CancellationError())
                }
            }
        }
    }
    private func takePending(_ id: UInt32, generation: Int, operation: UUID) -> Pending? {
        guard let entry = pending[id], entry.generation == generation, entry.operation == operation
        else { return nil }
        return pending.removeValue(forKey: id)
    }
    private func finishPendingIfComplete(_ id: UInt32, generation: Int, operation: UUID) {
        guard let candidate = pending[id], candidate.generation == generation,
            candidate.operation == operation, candidate.writeCompleted,
            let body = candidate.responseBody,
            let entry = takePending(id, generation: generation, operation: operation)
        else { return }
        entry.timeout.cancel()
        entry.continuation.resume(returning: body)
    }
    private func receive(_ data: Data, fromTCP: Bool) {
        guard fromTCP == isTCP else { return }
        if !fromTCP, !data.isEmpty { bleHasNotification = true }
        let frames = fromTCP ? tcpParser.feed(data) : bleParser.feed(data)
        for frame in frames {
            do {
                if frame.type == UCD2Frame.heartbeatType, fromTCP {
                    tcpGreetingSeen = true
                    tcpGreetingTimeout?.cancel()
                    tcpGreetingTimeout = nil
                    let waiter = tcpGreetingWaiter
                    tcpGreetingWaiter = nil
                    greetingOperation = nil
                    waiter?.resume()
                    continue
                }
                if frame.type == UCD2Frame.mediaType, fromTCP {
                    guard liveStartAttempted else { continue }
                    let media = try LunaMediaPacket(frame: frame)
                    if let video = media.hevcAnnexB {
                        eventHandler?(
                            .videoAccessUnit(video, timestampMilliseconds: media.timestamp))
                    }
                    continue
                }
                guard frame.type == UCD2Frame.messageType else { continue }
                let message: UCD2Message
                if frame.isScheme3Encrypted {
                    guard let sessionKey else {
                        throw CameraBackendError.unavailable(
                            "An encrypted camera message arrived outside its authorized session.")
                    }
                    let envelope = try frame.scheme3Envelope()
                    guard !receivedNonces.contains(envelope.nonce) else { continue }
                    let box = try AES.GCM.SealedBox(
                        nonce: AES.GCM.Nonce(data: envelope.nonce), ciphertext: envelope.ciphertext,
                        tag: envelope.tag)
                    let plaintext = try AES.GCM.open(
                        box, using: sessionKey, authenticating: envelope.associatedData)
                    receivedNonces.insert(envelope.nonce)
                    guard receivedNonces.count <= 4096 else {
                        throw CameraBackendError.unavailable(
                            "The encrypted camera session exceeded its bootstrap limit.")
                    }
                    message = try UCD2Message(payload: plaintext)
                } else {
                    guard let plain = try frame.plainMessage() else { continue }
                    message = plain
                }
                if message.code == 8209 || message.code == 8228 {
                    guard !fromTCP, authorizationOperation != nil else { continue }
                    approval = message
                    if let waiter = approvalWaiter {
                        approvalWaiter = nil
                        approvalTimeout?.cancel()
                        authorizationOperation = nil
                        do {
                            try LunaProtocol.validateAuthorizationNotification(message)
                            waiter.resume()
                        } catch { waiter.resume(throwing: error) }
                    }
                    continue
                }
                guard message.code == 200 || message.code == 500,
                    var waiting = pending[message.identifier], waiting.generation == generation,
                    waiting.responseBody == nil
                else { continue }
                do {
                    waiting.responseBody = try message.successfulResponseBody(
                        for: message.identifier, encrypted: frame.isScheme3Encrypted,
                        requiresEncryption: waiting.encrypted)
                    pending[message.identifier] = waiting
                    // Notifications can precede CoreBluetooth's write acknowledgement.
                    // The next command cannot start until BOTH sides have completed.
                    finishPendingIfComplete(
                        message.identifier, generation: generation, operation: waiting.operation)
                } catch {
                    if let entry = takePending(
                        message.identifier, generation: generation, operation: waiting.operation)
                    {
                        entry.timeout.cancel()
                        entry.continuation.resume(throwing: error)
                    }
                }
            } catch {
                failPending(error)
                if handshakeComplete {
                    transportDropped(
                        "The camera sent a message that could not be authenticated or decoded.")
                }
            }
        }
    }
    private func waitForTCPGreeting() async throws {
        if tcpGreetingSeen { return }
        let token = generation
        let operation = UUID()
        greetingOperation = operation
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                tcpGreetingWaiter = continuation
                tcpGreetingTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    guard !Task.isCancelled, let self, self.generation == token,
                        self.greetingOperation == operation, let waiter = self.tcpGreetingWaiter
                    else { return }
                    self.tcpGreetingWaiter = nil
                    self.greetingOperation = nil
                    waiter.resume(
                        throwing: CameraBackendError.unavailable(
                            "The camera did not complete the video connection greeting."))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.greetingOperation == operation else {
                    return
                }
                self.failPending(CancellationError())
            }
        }
    }
    private func waitForApproval() async throws {
        guard let operation = authorizationOperation else {
            throw CameraBackendError.unavailable("No camera approval request is active.")
        }
        let token = generation
        defer {
            if generation == token, authorizationOperation == operation {
                authorizationOperation = nil
                approval = nil
            }
        }
        if let approval {
            try LunaProtocol.validateAuthorizationNotification(approval)
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                approvalWaiter = continuation
                approvalTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled, let self, self.generation == token,
                        self.authorizationOperation == operation, let waiter = self.approvalWaiter
                    else { return }
                    self.approvalWaiter = nil
                    self.authorizationOperation = nil
                    waiter.resume(
                        throwing: CameraBackendError.unavailable(
                            "Camera approval timed out. Reconnect and accept the request on the camera's screen."
                        ))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.authorizationOperation == operation
                else { return }
                self.failPending(CancellationError())
            }
        }
    }
    private func startHeartbeat(token: Int) {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(LunaProtocol.heartbeatInterval))
                    guard let self, token == self.generation else { return }
                    let frame = try LunaProtocol.heartbeat(sequence: self.counter.nextSequence())
                    try await self.tcp.send(frame.raw)
                } catch {
                    if !Task.isCancelled {
                        self?.transportDropped(
                            "The camera stopped responding to the live connection.")
                    }
                    return
                }
            }
        }
    }
    private func transportDropped(_ reason: String) {
        failPending(CameraBackendError.unavailable(reason))
        guard handshakeComplete else { return }
        disconnect()
        eventHandler?(.disconnected(reason: reason))
    }
    private func failPending(_ error: Error) {
        greetingOperation = nil
        authorizationOperation = nil
        tcpGreetingTimeout?.cancel()
        tcpGreetingTimeout = nil
        let greeting = tcpGreetingWaiter
        tcpGreetingWaiter = nil
        greeting?.resume(throwing: error)
        let entries = pending
        pending.removeAll()
        for entry in entries.values {
            entry.timeout.cancel()
            entry.continuation.resume(throwing: error)
        }
        approvalTimeout?.cancel()
        approvalTimeout = nil
        let waiter = approvalWaiter
        approvalWaiter = nil
        waiter?.resume(throwing: error)
    }
}

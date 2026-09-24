import CryptoKit
import Foundation
import Insta360Protocol
import MonitorContracts
import os

/// Insta360 camera adapter. Live video plus captured Luna Ultra controls.
/// BLE performs consent and encrypted credential bootstrap; TCP carries UCD2 video.
@MainActor
public final class LunaCameraBackend: CameraBackend {
    public let capabilities: CameraCapabilities = [
        .liveVideo, .recording, .exposure, .captureFormat, .whiteBalance, .focus, .zoom, .gimbal,
        .cameraMedia,
    ]
    public var eventHandler: ((CameraBackendEvent) -> Void)?
    public var isOnCameraNetwork: Bool { LunaWiFi.localAddress != nil }
    private let log = Logger(subsystem: "com.opencapture.openinstacine", category: "luna")
    private let bluetooth = LunaBluetooth()
    private let tcp = LunaTCPTransport()
    private let existingNetwork: Bool
    private let identityOverride: UUID?
    private let colorRecoveryLab: Bool
    private let autoSet73: Bool
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
    private var recoveryOffTask: Task<Void, Never>?
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
    public init(useExistingNetwork: Bool = false, authorizedIdentity: UUID? = nil,
                colorRecoveryLab: Bool = false, autoSet73: Bool = false) {
        existingNetwork = useExistingNetwork
        identityOverride = authorizedIdentity
        self.colorRecoveryLab = colorRecoveryLab
        self.autoSet73 = autoSet73
        bluetooth.onCamera = { [weak self] camera in
            guard let self else { return }
            self.eventHandler?(
                .discovered(
                    MonitorCamera(
                        id: camera.id, name: camera.name, model: camera.model,
                        capabilities: self.capabilities)))
        }
        bluetooth.onData = { [weak self] in self?.receive($0, fromTCP: false) }
        bluetooth.onDisconnect = { [weak self] reason in self?.transportDropped(reason) }
        tcp.onData = { [weak self] in self?.receive($0, fromTCP: true) }
        tcp.onDisconnect = { [weak self] reason in self?.transportDropped(reason) }
    }
    public var labReady: Bool { handshakeComplete && isTCP }
    public var labWifiAddress: String? { LunaWiFi.localAddress }

    /// Phone-side lab: BLE + camera Wi-Fi + TCP, Mac stays on internet.
    public func startColorRecoveryLab() async throws {
        var cameras: [MonitorCamera] = []
        let previous = eventHandler
        eventHandler = { event in
            if case .discovered(let camera) = event { cameras.append(camera) }
            previous?(event)
        }
        defer { eventHandler = previous }
        try await startScan()
        let deadline = Date().addingTimeInterval(30)
        while cameras.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard let camera = cameras.first else {
            throw CameraBackendError.unavailable("No Luna camera advertised over Bluetooth.")
        }
        try await connect(to: camera)
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
                log.info("luna: BLE connect \(camera.name, privacy: .public)")
                try await bluetooth.connect(id: camera.id)
                try validate(token)
                log.info("luna: GATT ready")
                let greetingDeadline = Date().addingTimeInterval(5)
                while !bleHasNotification, Date() < greetingDeadline {
                    try validate(token)
                    try await Task.sleep(for: .milliseconds(50))
                }
                // The verified client proceeds with GetOptions after this bounded
                // notification grace, even when the camera omits its initial greeting.
                try validate(token)
                eventHandler?(.phase(.negotiating))
                log.info("luna: GetOptions")
                NSLog("OpenInstaCine luna: GetOptions")
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
                eventHandler?(.phase(.awaitingApproval))
                log.info("luna: authorization check")
                NSLog("OpenInstaCine luna: authorization check")
                let authorization = try LunaProtocol.authorizationStatus(
                    response: await request(LunaProtocol.authorizationCheck(identity: identity)))
                if authorization == .approvalRequired {
                    authorizationOperation = UUID()
                    _ = try await request(LunaProtocol.requestAuthorization)
                    try await waitForApproval(identity: identity)
                } else if authorization != .authorized {
                    throw CameraBackendError.unavailable(
                        "The camera is in use by another connection. Close Insta360 on the other device, then reconnect."
                    )
                }
                log.info("luna: authorized, reading Wi-Fi")
                NSLog("OpenInstaCine luna: authorized, reading Wi-Fi")
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
            reportScreenAddressIfNeeded()
            recoveryOffTask = Task { @MainActor [weak self] in
                await self?.turnColorRecoveryOff()
            }
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
            if colorRecoveryLab {
                if autoSet73 {
                    try await writeColorRecoveryLabReport()
                }
                handshakeComplete = true
                eventHandler?(.phase(.idle))
                return
            }
            liveStartAttempted = true
            _ = try await request(LunaProtocol.startLiveRequest)
            try validate(token)
            streaming = true
            handshakeComplete = true
            eventHandler?(.phase(.streaming))
            if let recoveryOffTask {
                await recoveryOffTask.value
            } else {
                await turnColorRecoveryOff()
            }
            try? await refreshStatus()
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
        recoveryOffTask?.cancel()
        recoveryOffTask = nil
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
    /// Say so up front when Color Recovery cannot work, rather than letting the
    /// SET fail later with a bare timeout. The camera invites only the screen's
    /// address, and the app cannot set that address itself on any Apple platform.
    private func reportScreenAddressIfNeeded() {
        guard let instruction = LunaWiFi.screenAddressInstruction() else {
            log.info("luna: holding the screen address")
            NSLog("OpenInstaCine luna: holding the screen address")
            return
        }
        NSLog("OpenInstaCine luna: NOT on \(LunaWiFi.screenAddress); have \(LunaWiFi.localAddress ?? "none")")
        eventHandler?(.note("Color Recovery needs this device at \(LunaWiFi.screenAddress). \(instruction)"))
        log.error("luna: not on the screen address")
    }

    /// Always send OFF. Unknown is not off — that reversal was a client bug.
    private func turnColorRecoveryOff() async {
        if await tryPhoneRecoveryOff() {
            eventHandler?(.note("Color Recovery off (phone protocol)"))
            return
        }
        _ = await LunaWiFi.claimScreenAddress()
        reportScreenAddressIfNeeded()
        do {
            NSLog("OpenInstaCine luna: sending Color Recovery OFF")
            try await LunaScreenRecovery.disableColorRecovery(localAddress: LunaWiFi.localAddress)
            eventHandler?(.note("Color Recovery off"))
            log.info("luna: Color Recovery off accepted")
            NSLog("OpenInstaCine luna: Color Recovery OFF accepted")
        } catch {
            eventHandler?(
                .note("Color Recovery could not be turned off: \(error.localizedDescription)"))
            log.error("luna: Color Recovery off failed \(error.localizedDescription, privacy: .public)")
            NSLog("OpenInstaCine luna: Color Recovery OFF failed: \(error.localizedDescription)")
        }
    }

    /// Untried phone-protocol shapes for option 73. A varint SET is ACKed and
    /// ignored if the field is actually a nested message (GET stays omitted).
    private func tryPhoneRecoveryOff() async -> Bool {
        var logRows: [[String: String]] = []
        func row(
            _ label: String, _ reading: LunaProtocol.PhotographyReading? = nil, extra: String = ""
        ) {
            let integers = reading?.integers[73].map(String.init) ?? "omitted"
            let blob = reading?.blobs[73]?.map { String(format: "%02x", $0) }.joined() ?? ""
            logRows.append([
                "label": label, "int73": integers, "blob73": blob, "extra": extra,
            ])
            NSLog("OpenInstaCine recovery-probe %@ int=%@ blob=%@", label, integers, blob)
        }
        func get73() async -> LunaProtocol.PhotographyReading? {
            try? LunaProtocol.photographyReading(
                await request(LunaProtocol.getPhotographyOptions([35, 72, 73])))
        }
        do {
            row("GET before", await get73())
            _ = try await request(LunaProtocol.setColorMode(.iLog))
            row("GET after I-Log", await get73())

            let attempts: [(String, LunaRequest)] = [
                ("nested 0/0/100", try LunaProtocol.setColorRecoveryNested(enable: false, lutType: 0)),
                ("nested 0/1/100", try LunaProtocol.setColorRecoveryNested(enable: false, lutType: 1)),
                ("named kStandard", try LunaProtocol.setColorRecoveryNamed(enable: false, lutType: "kStandard")),
                ("flag 0", try LunaProtocol.setColorRecoveryFlag(false)),
                (
                    "72+73 nested",
                    try LunaProtocol.setPhotographyOptions(
                        types: [72, 73],
                        nested: try ProtoMessage.integer(field: 72, value: 1)
                            + ProtoMessage.blob(
                                field: 73,
                                value: try ProtoMessage.integer(field: 1, value: 0)
                                    + ProtoMessage.integer(field: 2, value: 0)
                                    + ProtoMessage.integer(field: 3, value: 100)),
                        mode: 7)
                ),
            ]
            for (label, requestBody) in attempts {
                _ = try await request(requestBody)
                try await Task.sleep(for: .milliseconds(300))
                let reading = await get73()
                row("GET after \(label)", reading)
                if reading?.integers[73] == 0 {
                    writeRecoveryProbe(logRows, note: "int73-zero \(label)")
                    return true
                }
            }

            if let json = try? await request(LunaProtocol.getCameraParamsJSONRequest) {
                let text = String(data: json, encoding: .utf8)
                    ?? json.map { String(format: "%02x", $0) }.joined()
                row("GET 216", extra: String(text.prefix(400)))
            }
            for command in ["iq_ilog_lut.enable=false", "color_recovery=0", "set color_recovery off"] {
                if let reply = try? await request(LunaProtocol.execCmd(command)) {
                    row("exec \(command)", extra: reply.map { String(format: "%02x", $0) }.joined())
                }
            }
        } catch {
            row("error", extra: String(describing: error))
        }
        writeRecoveryProbe(logRows, note: "no-phone-hit")
        return false
    }

    private func writeRecoveryProbe(_ rows: [[String: String]], note: String) {
        let payload: [String: Any] = [
            "utc": ISO8601DateFormatter().string(from: Date()),
            "note": note,
            "address": LunaWiFi.localAddress ?? "",
            "interface": LunaWiFi.cameraInterface ?? "",
            "holds253": LunaWiFi.holdsScreenAddress,
            "rows": rows,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.prettyPrinted]),
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("recovery-probe.json")
        else { return }
        try? data.write(to: url, options: .atomic)
        NSLog("OpenInstaCine recovery-probe wrote %@", url.path)
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
                            "The camera did not answer connection command \(request.wireCode). Reconnect and try again."
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
                NSLog(
                    "OpenInstaCine luna: RX code=%u id=%u encrypted=%d tcp=%d",
                    UInt32(message.code), message.identifier, frame.isScheme3Encrypted ? 1 : 0,
                    fromTCP ? 1 : 0)
                if message.code == 8209 || message.code == 8228 {
                    guard !fromTCP else { continue }
                    // The camera can emit 8209 as soon as GATT is up, before we
                    // send command 86. Keep the notice for waitForApproval.
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
    private func waitForApproval(identity: UUID) async throws {
        let token = generation
        let deadline = Date().addingTimeInterval(90)
        defer {
            if generation == token {
                authorizationOperation = nil
            }
        }
        while Date() < deadline {
            try validate(token)
            if let approval {
                try LunaProtocol.validateAuthorizationNotification(approval)
                return
            }
            let status = try LunaProtocol.authorizationStatus(
                response: await request(LunaProtocol.authorizationCheck(identity: identity)))
            if status == .authorized { return }
            if status != .approvalRequired {
                throw CameraBackendError.unavailable(
                    "The camera is in use by another connection. Close Insta360 on the other device, then reconnect."
                )
            }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw CameraBackendError.unavailable(
            "Camera approval timed out. Reconnect and accept the request on the camera's screen.")
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

    public func apply(_ intent: CameraControlIntent) async throws {
        guard handshakeComplete, isTCP else {
            throw CameraBackendError.unavailable("Connect the camera before sending controls.")
        }
        switch intent {
        case .record(let start):
            _ = try await request(start ? LunaProtocol.startCaptureRequest : LunaProtocol.stopCaptureRequest)
            try await refreshStatus()
        case .takePhoto:
            _ = try await request(LunaProtocol.takePictureRequest)
        case .zoom(let factor):
            _ = try await request(LunaProtocol.setZoomScale(factor))
            try await refreshStatus()
        case .gimbal(let pan, let tilt):
            _ = try await request(LunaProtocol.gimbalStick(pan: pan, tilt: tilt))
        case .recenterGimbal:
            _ = try await request(LunaProtocol.gimbalRecenterRequest())
            _ = try await request(LunaProtocol.cancelTrackingRequest)
        case .flipGimbal:
            _ = try await request(LunaProtocol.gimbalFlipRequest())
        case .stopGimbal:
            _ = try await request(LunaProtocol.gimbalReleaseRequest())
        case .focus(let x, let y):
            _ = try await request(LunaProtocol.setTapFocus(x: x, y: y))
        case .track(let x, let y, let width, let height):
            _ = try await request(LunaProtocol.openTracking(x: x, y: y, width: width, height: height))
        case .stopTracking:
            _ = try await request(LunaProtocol.cancelTrackingRequest)
        case .videoFormat(let resolution, _, let framesPerSecond):
            _ = try await request(
                LunaProtocol.setRecordResolution(
                    Self.recordResolution(named: resolution, framesPerSecond: framesPerSecond)))
            try await refreshStatus()
        case .parameter(let key, let value):
            try await applyParameter(key, value)
        }
    }

    public func refreshStatus() async throws {
        guard handshakeComplete, isTCP else { return }
        let types: [UInt32] = [7, 21, 31, 35, 39, 53]
        let reading = try LunaProtocol.photographyReading(
            await request(LunaProtocol.getPhotographyOptions(types)))
        let capture = try? ProtoMessage(
            await request(LunaProtocol.captureStatusRequest))
        eventHandler?(.status(Self.snapshot(reading: reading, capture: capture)))
        if let color = reading.integers[35], color == 2 {
            eventHandler?(
                .information(
                    CameraInformation(
                        model: LunaProtocol.model, previewTransfer: .iLog)))
        }
    }

    public func listMedia() async throws -> [CameraMediaAsset] {
        guard handshakeComplete, isTCP else {
            throw CameraBackendError.unavailable("Connect the camera to browse clips.")
        }
        var assets: [CameraMediaAsset] = []
        var start: UInt32 = 0
        for _ in 0..<16 {
            let uris = try LunaProtocol.fileListURIs(
                await request(LunaProtocol.fileListRequest(start: start)))
            if uris.isEmpty { break }
            for uri in uris {
                let name = URL(fileURLWithPath: uri).lastPathComponent
                assets.append(
                    CameraMediaAsset(
                        id: uri, filename: name,
                        isPhoto: name.lowercased().hasSuffix(".jpg")
                            || name.lowercased().hasSuffix(".dng"),
                        canDelete: true))
            }
            if uris.count < 50 { break }
            start += UInt32(uris.count)
        }
        return assets
    }

    public func downloadMedia(
        _ asset: CameraMediaAsset, representation: CameraMediaRepresentation, to destination: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        guard handshakeComplete, isTCP else {
            throw CameraBackendError.unavailable("Connect the camera to download clips.")
        }
        _ = try await request(LunaProtocol.setAccessCameraFileState(1))
        _ = try await request(LunaProtocol.fileExtraRequest(asset.id))
        let path = asset.id.hasPrefix("http") ? asset.id : "http://\(LunaProtocol.defaultHost)\(asset.id)"
        let proxy = representation == .proxy ? path.replacingOccurrences(of: ".mp4", with: ".lrv") : path
        guard let url = URL(string: proxy) else {
            throw CameraBackendError.unavailable("The camera clip path was not a valid URL.")
        }
        let (bytes, _) = try await URLSession.shared.data(from: url)
        try bytes.write(to: destination, options: .atomic)
        progress(1)
    }

    public func deleteMedia(_ asset: CameraMediaAsset) async throws {
        guard asset.canDelete else {
            throw CameraBackendError.unavailable("This clip cannot be deleted.")
        }
        _ = try await request(LunaProtocol.deleteFiles(asset.id))
    }

    private func applyParameter(_ key: CameraParameter, _ value: CameraParameterValue) async throws {
        switch (key, value) {
        case (.iso, .automatic):
            _ = try await request(LunaProtocol.setVideoExposure(program: .automatic))
        case (.iso, .number(let iso)):
            _ = try await request(
                LunaProtocol.setVideoExposure(program: .isoPriority, iso: UInt64(iso.rounded())))
        case (.shutterSeconds, .number(let seconds)):
            _ = try await request(
                LunaProtocol.setVideoExposure(program: .shutterPriority, shutterSeconds: seconds))
        case (.exposureCompensationStops, .number(let stops)):
            _ = try await request(LunaProtocol.setExposureBias(stops))
        case (.exposureMode, .automatic):
            _ = try await request(LunaProtocol.setVideoExposure(program: .automatic))
        case (.exposureMode, .option(let mode)) where mode.rawValue == "auto":
            _ = try await request(LunaProtocol.setVideoExposure(program: .automatic))
        case (.colorProfile, .option(let mode)):
            _ = try await request(LunaProtocol.setColorMode(Self.colorMode(named: mode.rawValue)))
        case (.whiteBalanceKelvin, .number(let kelvin)):
            _ = try await request(LunaProtocol.setWhiteBalanceKelvin(UInt64(kelvin.rounded())))
        case (.whiteBalanceMode, .automatic):
            break
        case (.whiteBalanceMode, .option(let mode)) where mode.rawValue == "auto":
            break
        case (.shootingMode, .option(let mode)):
            _ = try await request(LunaProtocol.setVideoSubMode(Self.videoSubMode(named: mode.rawValue)))
        case (.colorRecovery, .boolean(let enabled)):
            try await LunaScreenRecovery.setRecovery(
                enabled: enabled, localAddress: LunaWiFi.localAddress)
        default:
            throw CameraBackendError.unavailable("This camera control is not captured for Luna yet.")
        }
        try await refreshStatus()
    }

    private static func colorMode(named raw: String) -> LunaColorMode {
        switch raw {
        case "iLog": .iLog
        case "dolbyVision": .dolbyVision
        default: .standard
        }
    }

    private static func videoSubMode(named raw: String) -> LunaVideoSubMode {
        switch raw {
        case "slowMo": .slowMotion
        case "timeLapse": .timelapse
        case "hyperLapse": .timeShift
        default: .normal
        }
    }

    private static func recordResolution(named resolution: String, framesPerSecond: Double) -> UInt64 {
        let fps = Int(framesPerSecond.rounded())
        let compact = resolution.lowercased().replacingOccurrences(of: " ", with: "")
        if compact.contains("9:16") || compact.contains("1728") { return 454 }
        if compact.contains("1080") { return 52 }
        if compact.contains("8k") || compact.contains("7680") { return 211 }
        if fps == 30 { return 24 }
        return 48
    }

    private static func snapshot(reading: LunaProtocol.PhotographyReading, capture: ProtoMessage?)
        -> CameraStatusSnapshot
    {
        var parameters: [CameraParameter: CameraParameterValue] = [:]
        if let color = reading.integers[35] {
            let name: String
            switch color {
            case 2: name = "iLog"
            case 5: name = "dolbyVision"
            default: name = "normal"
            }
            parameters[.colorProfile] = .option(.init(rawValue: name))
        }
        if let ev = reading.integers[7] {
            parameters[.exposureCompensationStops] = .number(Double(ev) / 20)
        }
        if let kelvin = reading.integers[39], kelvin >= 2000 {
            parameters[.whiteBalanceMode] = .option(.init(rawValue: "custom"))
            parameters[.whiteBalanceKelvin] = .number(Double(kelvin))
        }
        if let iso = reading.iso {
            parameters[.iso] = iso == 0 ? .automatic : .number(Double(iso))
        }
        if let seconds = reading.shutterSeconds, seconds > 0 {
            parameters[.shutterSeconds] = .number(seconds)
        }
        if let program = reading.exposureProgram {
            parameters[.exposureMode] = program == 0 ? .automatic : .option(.init(rawValue: "manual"))
        }
        let recording = (try? capture?.unsigned(1, default: 0)) ?? 0
        return CameraStatusSnapshot(
            recording: recording != 0,
            captureFramesPerSecond: reading.integers[31].flatMap(Self.framesPerSecond(forResolution:)),
            captureResolution: reading.integers[31].flatMap(Self.resolutionName(for:)),
            parameters: parameters)
    }

    private static func framesPerSecond(forResolution value: UInt64) -> Double? {
        switch value {
        case 24: 30
        case 48, 52, 211, 454: 25
        default: nil
        }
    }

    private static func resolutionName(for value: UInt64) -> String? {
        switch value {
        case 52: "1080"
        case 24, 48: "4K"
        case 454: "3K 9:16"
        case 211: "8K"
        default: nil
        }
    }

    public func labGetPhotography(types: [UInt32], mode: UInt32 = 7) async throws -> [Int: UInt64] {
        try labEnsureTCP()
        return try LunaProtocol.photographyValues(
            await request(LunaProtocol.getPhotographyOptions(types, mode: mode)))
    }

    public func labSetPhotography(field: UInt32, value: UInt64, mode: UInt32 = 7) async throws -> Data {
        try labEnsureTCP()
        let nested = try ProtoMessage.integer(field: Int(field), value: value)
        return try await request(
            LunaProtocol.setPhotographyOptions(types: [field], nested: nested, mode: mode))
    }

    public func labCommand(code: UInt16, body: Data) async throws -> Data {
        try labEnsureTCP()
        return try await request(LunaRequest(code: code, body: body))
    }

    public func labSet73Experiment() async throws -> [String: Any] {
        try labEnsureTCP()
        try await writeColorRecoveryLabReport()
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("set73-lab.json")
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func labEnsureTCP() throws {
        guard handshakeComplete, isTCP else {
            throw CameraBackendError.unavailable("The lab camera TCP session is not ready.")
        }
    }

    private func writeColorRecoveryLabReport() async throws {
        var log: [[String: String]] = []
        func snapshot(_ label: String, _ body: Data) throws {
            let values = try LunaProtocol.photographyValues(body)
            log.append([
                "label": label,
                "color_35": values[35].map(String.init) ?? "omitted",
                "ilog_72": values[72].map(String.init) ?? "omitted",
                "recovery_73": values[73].map(String.init) ?? "omitted",
            ])
        }
        let types: [UInt32] = [35, 72, 73]
        try await snapshot("GET initial", request(LunaProtocol.getPhotographyOptions(types)))
        if log.last?["color_35"] != "2" {
            let nested = try ProtoMessage.integer(field: 35, value: 2)
            _ = try await request(LunaProtocol.setPhotographyOptions(types: [35], nested: nested))
            try await snapshot("GET after I-Log SET", request(LunaProtocol.getPhotographyOptions(types)))
        }
        for (enabled, name) in [(true, "SET 73 on"), (false, "SET 73 off"), (true, "SET 73 on again")] {
            let nested = try ProtoMessage.integer(field: 73, value: enabled ? 1 : 0)
            _ = try await request(LunaProtocol.setPhotographyOptions(types: [73], nested: nested))
            try await Task.sleep(for: .milliseconds(400))
            try await snapshot("GET after \(name)", request(LunaProtocol.getPhotographyOptions(types)))
        }
        let afterOn = log.filter { $0["label"]?.contains("SET 73 on") == true }.map { $0["recovery_73"] ?? "" }
        let afterOff = log.filter { $0["label"]?.contains("SET 73 off") == true }.map { $0["recovery_73"] ?? "" }
        let proven = afterOn.contains("1") && afterOff.contains(where: { $0 == "0" || $0 == "omitted" })
        let report: [String: Any] = [
            "proven": proven,
            "after_on": afterOn,
            "after_off": afterOff,
            "log": log,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("set73-lab.json")
        try data.write(to: url, options: .atomic)
    }
}

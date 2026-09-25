#if DEBUG
    import CoreImage
    import Foundation
    import Insta360Protocol
    import Network
    import OpenPocketViewCore
    import UIKit

    /// DEBUG-only remote control for on-device testing without XCUITest.
    /// Listens on TCP 18780; the Mac reaches it over the CoreDevice tunnel
    /// (`tools/oic_remote.py`). Drives the real `AppModel` / `CameraSession`
    /// and returns screenshots, state and the control log. Never compiled into Release.
    @MainActor
    enum DebugRemote {
        static let port: UInt16 = 18_780
        private static var listener: NWListener?
        static var lastFrame: CVPixelBuffer?
        private static var logRing: [String] = []

        static func start() {
            guard listener == nil else { return }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            else { return }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .main)
                receive(connection, buffer: Data())
            }
            listener.start(queue: .main)
            self.listener = listener
        }

        static func noteLog(_ line: String) {
            logRing.append(line)
            if logRing.count > 400 { logRing.removeFirst(logRing.count - 400) }
        }

        nonisolated private static func receive(_ connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
                data, _, done, error in
                var next = buffer
                if let data { next.append(data) }
                if let request = HTTPRequest(next) {
                    Task { @MainActor in
                        let (status, type, body) = await handle(request)
                        var head = "HTTP/1.1 \(status) OK\r\nContent-Type: \(type)\r\n"
                        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                        var out = Data(head.utf8)
                        out.append(body)
                        connection.send(
                            content: out, completion: .contentProcessed { _ in connection.cancel() })
                    }
                    return
                }
                if done || error != nil {
                    connection.cancel()
                    return
                }
                receive(connection, buffer: next)
            }
        }

        private static func handle(_ request: HTTPRequest) async -> (Int, String, Data) {
            guard let model = AppModelDiagnosticsAnchor.model else {
                return (503, "application/json", json(["ok": false, "error": "no model yet"]))
            }
            switch (request.method, request.path) {
            case ("GET", "/health"):
                return (200, "application/json", json(["ok": true]))
            case ("GET", "/state"):
                return (200, "application/json", json(state(model)))
            case ("GET", "/log"):
                return (200, "text/plain", Data(ControlLiveLog.recentLines().suffix(300).joined(separator: "\n").utf8))
            case ("GET", "/screenshot"):
                return (200, "image/png", screenshot() ?? Data())
            case ("GET", "/frame"):
                return (200, "image/jpeg", frameJPEG() ?? Data())
            case ("POST", "/action"):
                let object = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
                let result = await perform(object ?? [:], model: model)
                return (200, "application/json", json(result))
            default:
                return (404, "application/json", json(["ok": false, "error": "not found"]))
            }
        }

        private static func json(_ object: Any) -> Data {
            (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
                ?? Data("{}".utf8)
        }

        private static func state(_ model: AppModel) -> [String: Any] {
            let s = model.session
            let st = s.status
            return [
                "phase": s.phase.label,
                "isLive": model.isLive,
                "found": s.found.map { ["id": $0.id.uuidString, "name": $0.name] },
                "saved": model.savedCameras.map { ["id": $0.id.uuidString, "name": $0.displayName] },
                "connected": s.connectedCamera?.name ?? "",
                "joinedSSID": s.joinedSSID != nil,
                "liveFPS": s.liveFPS,
                "signalBars": s.liveSignalBars,
                "isFeedWarming": s.isFeedWarming,
                "stale": s.isLiveVideoStale,
                "accessUnits": s.accessUnits,
                "framesEnqueued": s.framesEnqueued,
                "hasVideoFormat": s.hasVideoFormat,
                "controlNote": s.controlNote ?? "",
                "controlBusy": s.controlBusy,
                "recovery": String(describing: s.sessionRecovery),
                "battery": st.batteryPercent,
                "charging": st.charging,
                "storageFreeMb": st.storageFreeMb,
                "storageTotalMb": st.storageTotalMb,
                "recording": st.isRecording,
                "recordElapsed": st.recordElapsedSec,
                "shootingMode": s.currentShootingMode?.label ?? "\(st.shootingMode)",
                "expoMode": st.expoMode.map { "\($0)" } ?? "?",
                "iso": st.isoIndex?.label ?? "?",
                "shutter": st.shutterDenom,
                "ev": st.evComp?.label ?? "?",
                "wb": st.whiteBalance.map { $0.mode == .auto ? "auto" : "\($0.kelvin)K" } ?? "?",
                "color": st.colorMode?.label ?? "?",
                "format": st.videoFormat?.chipLabel ?? "?",
                "formats": st.availableVideoFormats.map(\.chipLabel),
                "zoom": s.zoomReadout,
                "zoomStops": s.zoomStops,
                "gimbalMode": s.gimbalMode.label,
                "gimbalSpeed": s.gimbalSpeed.label,
                "firmware": st.firmware ?? "",
                "tracking": s.isTracking,
                "focus": [s.focusPoint.x, s.focusPoint.y],
                "media": s.mediaFiles.count,
                "mediaNote": s.mediaNote ?? "",
                "homePanel": model.homePanel?.rawValue ?? "",
                "livePanel": model.liveOperatorPanel.map { "\($0)" } ?? "",
                "settingsTab": model.operatorSettingsTab.rawValue,
                "assists": LiveAssistTool.allCases.filter { model.assist.isOn($0) }.map(\.rawValue),
            ]
        }

        // swiftlint:disable:next cyclomatic_complexity function_body_length
        private static func perform(_ cmd: [String: Any], model: AppModel) async -> [String: Any] {
            let s = model.session
            let name = cmd["action"] as? String ?? ""
            func num(_ key: String) -> Double? {
                (cmd[key] as? NSNumber)?.doubleValue ?? (cmd[key] as? String).flatMap(Double.init)
            }
            func str(_ key: String) -> String? { cmd[key] as? String }
            switch name {
            case "scan": s.startScan()
            case "connectFirst":
                if let camera = s.found.first { s.connect(camera) } else { return ["ok": false, "error": "none found"] }
            case "reconnect":
                if let id = str("id").flatMap(UUID.init(uuidString:)) ?? model.savedCameras.first?.id {
                    s.reconnect(to: id)
                }
            case "disconnect": model.disconnect()
            case "record": s.pressShutter()
            case "mode":
                if let mode = ShootingMode.allCases.first(where: { $0.label == str("value") || "\($0)" == str("value") }) {
                    s.setShootingMode(mode)
                }
            case "iso":
                if str("value") == "auto" { s.setISO(.auto) } else if let v = num("value"), let idx = IsoIndex.allCases.first(where: { $0.isoValue == Int(v) }) {
                    s.setISO(idx)
                }
            case "shutter": if let v = num("value") { s.setShutterDenom(Int(v)) }
            case "expo": s.setExpoMode(str("value") == "auto" ? .auto : .manual)
            case "ev": if let v = num("value") { s.setEv(EvComp(thirds: Int((v * 3).rounded()))) }
            case "wb":
                if str("value") == "auto" { s.setWhiteBalanceAuto() } else if let k = num("value") {
                    s.setWhiteBalanceCustom(kelvin: Int(k), tint: 0)
                }
            case "color":
                if let mode = ColorMode.allCases.first(where: { $0.label == str("value") || "\($0)" == str("value") }) {
                    s.setColorMode(mode)
                }
            case "format":
                if let label = str("value"),
                    let format = s.status.availableVideoFormats.first(where: { $0.chipLabel == label })
                {
                    s.setVideoFormat(resolution: format.resolution, frameRate: format.frameRate)
                } else {
                    return ["ok": false, "error": "format not offered", "formats": s.status.availableVideoFormats.map(\.chipLabel)]
                }
            case "zoom": if let v = num("value") { s.setZoom(v) }
            case "pinch":
                let steps = Int(num("steps") ?? 10)
                let to = num("value") ?? 2
                for i in 1...max(1, steps) {
                    s.updateZoomPinch(magnification: 1 + (to - 1) * Double(i) / Double(steps))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                s.endZoomPinch()
            case "stick":
                let x = num("x") ?? 0
                let y = num("y") ?? 0
                let seconds = num("seconds") ?? 1
                let end = Date().addingTimeInterval(seconds)
                while Date() < end {
                    s.updateGimbalStick(x: x, y: y)
                    try? await Task.sleep(for: .milliseconds(30))
                }
                s.endGimbalStick()
            case "recenter": s.recenterGimbal()
            case "flip": s.flipGimbal()
            case "gimbalMode":
                if let mode = GimbalMode.allCases.first(where: { "\($0)" == str("value") }) { s.setGimbalMode(mode) }
            case "gimbalSpeed":
                if let speed = GimbalSpeed.allCases.first(where: { "\($0)" == str("value") }) { s.setGimbalSpeed(speed) }
            case "tap": s.handleFeedTap(at: CGPoint(x: num("x") ?? 0.5, y: num("y") ?? 0.5))
            case "track":
                s.startTracking(
                    TrackingBox(
                        x: (num("x") ?? 0.5) - (num("w") ?? 0.2) / 2,
                        y: (num("y") ?? 0.5) - (num("h") ?? 0.3) / 2,
                        width: num("w") ?? 0.2, height: num("h") ?? 0.3))
            case "cancelTrack": s.cancelSubjectTracking()
            case "lock": s.isLocked = cmd["value"] as? Bool ?? !s.isLocked
            case "panel":
                switch str("value") {
                case "settings": model.liveOperatorPanel = .settings
                case "media": model.liveOperatorPanel = .media
                case "homeSettings": model.homePanel = .settings
                case "homeMedia": model.homePanel = .media
                default:
                    model.liveOperatorPanel = nil
                    model.homePanel = nil
                }
            case "settingsTab":
                if let tab = OperatorSettingsTab.allCases.first(where: { $0.rawValue == str("value") || "\($0)" == str("value") }) {
                    model.operatorSettingsTab = tab
                }
            case "gimbalPanel":
                model.liveGimbalPanel = str("value") == "close" ? .none : .sheet
            case "sheet":
                model.captureSheet = str("value").flatMap(CaptureSheet.init(rawValue:))
            case "assist":
                if let tool = LiveAssistTool.allCases.first(where: { $0.rawValue == str("value") || "\($0)" == str("value") }) {
                    model.assist.toggle(tool)
                }
            case "clean": model.setDisplayMode(clean: cmd["value"] as? Bool ?? !model.assist.clean)
            case "pairNew": model.isPairingNewCamera = cmd["value"] as? Bool ?? true
            case "mediaBrowse": s.beginMediaBrowse()
            case "mediaEnd": s.endMediaBrowse()
            case "thumb":
                if let file = s.mediaFiles.first(where: { $0.filename == str("value") }) ?? s.mediaFiles.first {
                    await s.ensureThumbnail(for: file)
                    return ["ok": s.thumbnailURL(for: file) != nil, "file": file.filename]
                }
            case "download":
                if let file = s.mediaFiles.first(where: { $0.filename == str("value") }) ?? s.mediaFiles.first {
                    await s.download(file: file)
                    return ["ok": s.isDownloaded(file), "file": file.filename, "note": s.mediaNote ?? ""]
                }
            case "delete":
                guard let target = str("value"), let file = s.mediaFiles.first(where: { $0.filename == target }) else {
                    return ["ok": false, "error": "delete needs an exact filename"]
                }
                await s.deleteMedia(file)
            case "files":
                return ["ok": true, "files": s.mediaFiles.map { ["name": $0.filename, "bytes": $0.sizeBytes, "duration": $0.durationSeconds, "res": $0.resolution ?? "", "proxy": $0.proxyPath ?? ""] }]
            case "refreshStatus": await s.backend.refreshStatus()
            case "raw":
                guard let code = num("code") else { return ["ok": false] }
                let body = Data(hex: str("hex") ?? "")
                do {
                    let reply = try await s.backend.send(LunaRequest(code: UInt16(code), body: body))
                    return ["ok": true, "reply": reply.map { String(format: "%02x", $0) }.joined()]
                } catch {
                    return ["ok": false, "error": error.localizedDescription]
                }
            case "wait":
                try? await Task.sleep(for: .seconds(num("seconds") ?? 1))
            default:
                return ["ok": false, "error": "unknown action \(name)"]
            }
            try? await Task.sleep(for: .milliseconds(Int((num("pause") ?? 0.3) * 1000)))
            return ["ok": true, "action": name, "state": state(model)]
        }

        private static func screenshot() -> Data? {
            guard
                let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .first,
                let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            else { return nil }
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            return image.pngData()
        }

        private static func frameJPEG() -> Data? {
            guard let frame = lastFrame else { return nil }
            let image = CIImage(cvPixelBuffer: frame)
            return CIContext().jpegRepresentation(
                of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data

        init?(_ data: Data) {
            guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = String(decoding: data[..<split.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            let parts = lines.first?.split(separator: " ") ?? []
            guard parts.count >= 2 else { return nil }
            method = String(parts[0])
            path = String(parts[1].split(separator: "?").first ?? "")
            let length =
                lines.first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = data[split.upperBound...]
            guard body.count >= length else { return nil }
            self.body = Data(body.prefix(length))
        }
    }

    extension Data {
        init(hex: String) {
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
                if let byte = UInt8(hex[index..<next], radix: 16) { bytes.append(byte) }
                index = next
            }
            self.init(bytes)
        }
    }
#endif

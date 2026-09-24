import CoreGraphics
import Foundation
import ImageIO
import Insta360Protocol
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
usage: luna-probe [--fm N] <command>
  info                      device info (serial suffix only)
  status                    battery, storage, remaining time, capture status, mode
  get [types,...]           photography options for every FunctionMode (or --fm N)
  set <thing> <value...>    before/SET/after readback; see `set help`
  live <seconds> [out.hevc] start live, count access units / keyframes, stop
  notify <seconds>          log every notification
  files                     media list with metadata
  thumb <uri> <out.png>     cmd 11 type 2 thumbnail as PNG
  record <seconds>          start/stop a test clip (URIs saved as probe-created)
  photo                     take one picture (URIs saved as probe-created)
  delete <uri>              delete ONLY a probe-created file
  http <uri> [state] [range] [out]  cmd 118 access state then HTTP Range GET
  raw <code> <hexbody>      send any request and dump the reply
"""

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../../..").standardized
let createdList = root.appendingPathComponent(".local/lunaprobe-created.txt")

var arguments = Array(CommandLine.arguments.dropFirst())
var functionModeOverride: UInt32?
if let index = arguments.firstIndex(of: "--fm"), index + 1 < arguments.count {
    functionModeOverride = UInt32(arguments[index + 1])
    arguments.removeSubrange(index...index + 1)
}
guard let command = arguments.first else { print(usage); exit(2) }
let rest = Array(arguments.dropFirst())
let fm = functionModeOverride ?? 7

func identity() throws -> UUID {
    let data = try Data(contentsOf: root.appendingPathComponent(".local/luna-client-identity.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let text = json?["authorization_id"] as? String, let uuid = UUID(uuidString: text) else {
        throw ProbeError("no authorization_id in .local/luna-client-identity.json")
    }
    return uuid
}

func connect() throws -> Camera {
    let camera = Camera()
    try camera.open(identity: identity())
    return camera
}

func photography(_ camera: Camera, _ types: [UInt32], mode: UInt32) throws -> (LunaPhotographySettings, Data) {
    let body = try camera.request(LunaProtocol.getPhotographyOptions(types, mode: mode))
    return (try LunaPhotographySettings(response: body), body)
}

func nested(_ body: Data) -> String {
    let outer = try? ProtoMessage(body)
    return (try? outer?.optionalBytes(2)).flatMap { $0 }.map { dump($0) } ?? "{}"
}

func parseShutter(_ text: String) throws -> Double {
    let parts = text.split(separator: "/")
    if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 { return a / b }
    guard let value = Double(text) else { throw ProbeError("bad shutter \(text)") }
    return value
}

func number<T: LosslessStringConvertible>(_ index: Int, _ what: String) throws -> T {
    guard index < rest.count, let value = T(rest[index]) else { throw ProbeError("missing/invalid \(what)") }
    return value
}

// MARK: Media helpers

func mediaFiles(_ camera: Camera) throws -> [LunaMediaFile] {
    try LunaProtocol.fileInfoList(response: camera.request(LunaProtocol.fileInfoListRequest()))
}

func allURIs(_ camera: Camera) throws -> Set<String> {
    var uris = Set(try mediaFiles(camera).map(\.uri))
    // cmd 13 also lists .lrv proxies and sidecars that cmd 38 may hide.
    for type in [LunaMediaType.videoAndPhoto, .dng, .insData] {
        if let body = try? camera.request(LunaProtocol.fileListRequest(mediaType: type)) {
            uris.formUnion((try? LunaProtocol.fileList(response: body).uris) ?? [])
        }
    }
    return uris
}

func remember(_ uris: Set<String>) throws {
    guard !uris.isEmpty else { return }
    let old = (try? String(contentsOf: createdList, encoding: .utf8)) ?? ""
    try (old + uris.sorted().joined(separator: "\n") + "\n").write(to: createdList, atomically: true, encoding: .utf8)
    for uri in uris.sorted() { log("PROBE-CREATED \(uri)") }
}

func writePNG(_ thumbnail: LunaThumbnail, to url: URL) throws {
    let (w, h) = (thumbnail.width, thumbnail.height)
    var rgba = [UInt8](repeating: 255, count: w * h * 4)
    let nv12 = [UInt8](thumbnail.nv12)
    // BT.709 limited-range NV12 to RGB.
    for y in 0..<h {
        for x in 0..<w {
            let luma = Double(nv12[y * w + x]) - 16
            let c = w * h + (y / 2) * w + (x & ~1)
            let cb = Double(nv12[c]) - 128, cr = Double(nv12[c + 1]) - 128
            let r = 1.164 * luma + 1.793 * cr
            let g = 1.164 * luma - 0.213 * cb - 0.533 * cr
            let b = 1.164 * luma + 2.112 * cb
            let o = (y * w + x) * 4
            rgba[o] = UInt8(max(0, min(255, r)))
            rgba[o + 1] = UInt8(max(0, min(255, g)))
            rgba[o + 2] = UInt8(max(0, min(255, b)))
        }
    }
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ProbeError("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ProbeError("PNG encode failed") }
}

// MARK: Live analysis

/// Counts HEVC access units (VCL NAL with first_slice_segment_in_pic_flag)
/// and IRAP keyframes from Annex B payloads.
struct LiveStats {
    var packets = 0, bytes = 0, accessUnits = 0, keyframes = 0
    var nalTypes: [Int: Int] = [:]
    var firstPacket: Date?, firstKeyframe: Date?, lastPacket: Date?
    var keyframeAUIndex: [Int] = []
    var timestamps: [UInt64] = []

    mutating func add(_ annexB: Data) {
        packets += 1
        bytes += annexB.count
        let now = Date()
        firstPacket = firstPacket ?? now
        lastPacket = now
        let b = [UInt8](annexB)
        var i = 0
        while i + 3 < b.count {
            if b[i] == 0, b[i + 1] == 0, b[i + 2] == 1 {
                let start = i + 3
                guard start + 2 < b.count else { break }
                let type = Int(b[start] >> 1) & 0x3F
                nalTypes[type, default: 0] += 1
                if type < 32, b[start + 2] & 0x80 != 0 {
                    accessUnits += 1
                    if (16...21).contains(type) {
                        keyframes += 1
                        keyframeAUIndex.append(accessUnits)
                        firstKeyframe = firstKeyframe ?? now
                    }
                }
                i = start
            } else {
                i += 1
            }
        }
    }
}

// MARK: Commands

func runSet(_ camera: Camera) throws {
    guard let thing = rest.first else { throw ProbeError("set what?") }
    let value = rest.count > 1 ? rest[1] : ""
    var readback: [UInt32] = []
    var deviceReadback = false
    let request: LunaRequest
    switch thing {
    case "color":
        let modes: [String: LunaColorMode] = ["standard": .standard, "ilog": .iLog, "vivid": .vivid, "hdr": .hdr, "dolby": .dolbyVision]
        guard let mode = modes[value] ?? UInt64(value).flatMap(LunaColorMode.init(rawValue:)) else { throw ProbeError("color standard|ilog|vivid|hdr|dolby") }
        request = try LunaProtocol.setColorMode(mode, functionMode: fm)
        readback = [35, 72]
    case "sharpness":
        request = try LunaProtocol.setSharpness(number(1, "level"), functionMode: fm)
        readback = [6]
    case "ev":
        request = try LunaProtocol.setExposureBias(number(1, "stops"), functionMode: fm)
        readback = [7]
    case "exposure-auto":
        request = try LunaProtocol.setVideoExposure(program: .automatic, functionMode: fm)
        readback = [21, 24, 100]
    case "iso":
        request = value == "auto"
            ? try LunaProtocol.setVideoExposure(program: .automatic, functionMode: fm)
            : try LunaProtocol.setVideoExposure(program: .isoPriority, iso: number(1, "iso"), functionMode: fm)
        readback = [21, 24, 100]
    case "shutter":
        request = try LunaProtocol.setVideoExposure(program: .shutterPriority, shutterSeconds: parseShutter(value), functionMode: fm)
        readback = [21, 24, 100]
    case "manual":
        request = try LunaProtocol.setManualExposure(iso: number(1, "iso"), shutterSeconds: parseShutter(rest.count > 2 ? rest[2] : ""), functionMode: fm)
        readback = [21, 24, 100]
    case "manual-shutter":
        request = try LunaProtocol.setVideoExposure(program: .manual, shutterSeconds: parseShutter(value), functionMode: fm)
        readback = [21, 24, 100]
    case "wb":
        request = value == "auto"
            ? try LunaProtocol.setWhiteBalanceAuto(functionMode: fm)
            : try LunaProtocol.setWhiteBalanceKelvin(number(1, "kelvin"), functionMode: fm)
        readback = [39]
    case "res":
        request = try LunaProtocol.setRecordResolution(number(1, "enum"), functionMode: fm)
        readback = [31]
    case "zoom":
        request = try LunaProtocol.setZoomScale(number(1, "factor"), functionMode: fm)
        readback = [53]
    case "gimbal-mode":
        guard let mode = UInt64(value).flatMap(LunaGimbalMode.init(rawValue:)) else { throw ProbeError("gimbal-mode 1..6") }
        request = try LunaProtocol.setGimbalMode(mode, functionMode: fm)
        readback = [91]
    case "follow-speed":
        guard let speed = UInt64(value).flatMap(LunaGimbalFollowSpeed.init(rawValue:)) else { throw ProbeError("follow-speed 1..4") }
        request = try LunaProtocol.setGimbalFollowSpeed(speed, functionMode: fm)
        readback = [91]
    case "focus":
        request = try LunaProtocol.setTapFocus(x: number(1, "x"), y: number(2, "y"), functionMode: fm)
        readback = [93, 94]
    case "value":
        let type: UInt32 = try number(1, "type")
        guard let known = LunaPhotographyType(rawValue: type) else { throw ProbeError("type \(type) has no encoder; use raw") }
        request = try LunaProtocol.setPhotographyValue(known, number(2, "value"), functionMode: fm)
        readback = [type]
    case "colorrecovery":
        request = try LunaProtocol.setColorRecoveryFlag(value == "1", functionMode: fm)
        readback = [73, 35]
    case "mode":
        let modes: [String: LunaShootingMode] = ["video": .video, "timelapse": .timelapse, "timeshift": .timeShift,
                                                "slowmo": .slowMotion, "purevideo": .pureVideo, "photo": .photo, "pano": .pano]
        guard let mode = modes[value] else { throw ProbeError("mode " + modes.keys.sorted().joined(separator: "|")) }
        request = try mode.request()
        deviceReadback = true
    case "recenter": request = try LunaProtocol.gimbalRecenterRequest()
    case "flip": request = try LunaProtocol.gimbalFlipRequest()
    case "release": request = try LunaProtocol.gimbalReleaseRequest()
    case "move": request = try LunaProtocol.gimbalMove(upDown: number(1, "upDown"), leftRight: number(2, "leftRight"))
    case "stick": request = try LunaProtocol.gimbalStick(pan: number(1, "pan"), tilt: number(2, "tilt"))
    case "track":
        request = try LunaProtocol.openTracking(x: number(1, "x"), y: number(2, "y"), width: number(3, "w"), height: number(4, "h"))
    case "track-cancel": request = LunaProtocol.cancelTrackingRequest
    default:
        throw ProbeError("unknown set target \(thing)")
    }
    func readState() throws -> String {
        if deviceReadback {
            let body = try camera.request(LunaProtocol.shootingModeRequest())
            let status = try LunaDeviceStatus(response: body)
            return "mode=\(status.shootingMode.map { "\($0)" } ?? "?") photo=\(status.photoSubMode.map(String.init) ?? "-") video=\(status.videoSubMode.map(String.init) ?? "-")"
        }
        guard !readback.isEmpty else { return "-" }
        let (settings, body) = try photography(camera, readback, mode: fm)
        return "\(describe(settings)) raw=\(nested(body))"
    }
    let before = try readState()
    log("BEFORE \(before)")
    log("TX cmd \(request.wireCode) body \(hex(request.body))")
    let reply = try camera.send(request)
    let replyText = reply.code == 200 ? ((try? LunaPhotographySettings(response: reply.body)).map { "types=\($0.types)" } ?? "") : ""
    log("REPLY \(reply.code) \(replyText) raw=\(hex(reply.body))")
    if thing == "move" || thing == "stick" {
        Thread.sleep(forTimeInterval: Double(rest.count > 3 ? rest[3] : "0.5") ?? 0.5)
        log("release \(try camera.send(LunaProtocol.gimbalReleaseRequest()).code)")
    }
    // Some options (WB, sharpness) apply asynchronously: poll up to 4 s for a change.
    let sent = Date()
    var after = before
    let maxWait = Double(ProcessInfo.processInfo.environment["LUNA_WAIT"] ?? "4") ?? 4
    while Date().timeIntervalSince(sent) < maxWait {
        Thread.sleep(forTimeInterval: 0.25)
        after = try readState()
        if after != before { break }
    }
    log(String(format: "AFTER (%.2fs) ", Date().timeIntervalSince(sent)) + after)
    print("RESULT \(thing) \(rest.dropFirst().joined(separator: " ")) fm=\(fm) reply=\(reply.code) before=[\(before)] after=[\(after)]")
}

func runLive(_ camera: Camera, seconds: Double, out: String?) throws {
    var stats = LiveStats()
    var file: FileHandle?
    if let out {
        FileManager.default.createFile(atPath: out, contents: nil)
        file = FileHandle(forWritingAtPath: out)
    }
    var subtypes: [UInt8: Int] = [:]
    var tickDeltas: [UInt64: Int] = [:]
    var lastTick: UInt64?
    camera.onMedia = { packet in
        subtypes[packet.subtype, default: 0] += 1
        guard let video = packet.hevcAnnexB else { return }
        if let lastTick { tickDeltas[packet.timestamp &- lastTick, default: 0] += 1 }
        lastTick = packet.timestamp
        stats.add(video)
        file?.write(video)
    }
    let sent = Date()
    log("TX start live \(hex(LunaProtocol.startLiveRequest.body))")
    let reply = try camera.send(LunaProtocol.startLiveRequest)
    log("start live reply \(reply.code) raw=\(hex(reply.body)) after \(String(format: "%.3f", Date().timeIntervalSince(sent)))s")
    Thread.sleep(forTimeInterval: seconds)
    let stop = try camera.send(LunaProtocol.stopLiveRequest)
    Thread.sleep(forTimeInterval: 0.3)
    try? file?.close()
    let span = stats.lastPacket.flatMap { l in stats.firstPacket.map { l.timeIntervalSince($0) } } ?? 0
    let gaps = zip(stats.keyframeAUIndex.dropFirst(), stats.keyframeAUIndex).map { $0 - $1 }
    print("""
    LIVE stop=\(stop.code) packets=\(stats.packets) bytes=\(stats.bytes) accessUnits=\(stats.accessUnits) keyframes=\(stats.keyframes)
      fps(wall)=\(span > 0 ? String(format: "%.2f", Double(stats.accessUnits - 1) / span) : "-") bitrate=\(span > 0 ? String(format: "%.2f Mbit/s", Double(stats.bytes) * 8 / span / 1e6) : "-")
      firstPacket=\(stats.firstPacket.map { String(format: "%.3fs", $0.timeIntervalSince(sent)) } ?? "-") firstKeyframe=\(stats.firstKeyframe.map { String(format: "%.3fs", $0.timeIntervalSince(sent)) } ?? "-")
      keyframeIntervalAUs=\(gaps) nalTypes=\(stats.nalTypes.sorted { $0.key < $1.key }) subtypes=\(subtypes) tickDeltas=\(tickDeltas.sorted { $0.value > $1.value }.prefix(4))
    """)
}

func runRecord(_ camera: Camera, seconds: Int) throws {
    let before = try allURIs(camera)
    log("files before: \(before.count)")
    log("capture status \(describe(try LunaCaptureStatus(captureStatusResponse: camera.request(LunaProtocol.captureStatusRequest))))")
    log("TX start capture \(hex(LunaProtocol.startCaptureRequest.body))")
    let start = try camera.send(LunaProtocol.startCaptureRequest)
    log("start reply \(start.code) raw=\(hex(start.body)) \(dump(start.body))")
    guard start.code == 200 else { return }
    for _ in 0..<seconds {
        Thread.sleep(forTimeInterval: 1)
        let body = try camera.request(LunaProtocol.captureStatusRequest)
        log("capture status \(describe(try LunaCaptureStatus(captureStatusResponse: body))) raw=\(dump(body))")
    }
    let stop = try camera.send(LunaProtocol.stopCaptureRequest, timeout: 15)
    log("stop reply \(stop.code) raw=\(hex(stop.body)) \(dump(stop.body)) video=\(describe((try? LunaProtocol.stoppedVideo(response: stop.body)) as Any))")
    Thread.sleep(forTimeInterval: 2)
    log("capture status \(describe(try LunaCaptureStatus(captureStatusResponse: camera.request(LunaProtocol.captureStatusRequest))))")
    try remember(try allURIs(camera).subtracting(before))
}

func runPhoto(_ camera: Camera) throws {
    let before = try allURIs(camera)
    let reply = try camera.send(LunaProtocol.takePictureRequest, timeout: 20)
    log("take picture reply \(reply.code) raw=\(hex(reply.body)) \(dump(reply.body))")
    for _ in 0..<5 {
        Thread.sleep(forTimeInterval: 1)
        log("capture status \(describe(try LunaCaptureStatus(captureStatusResponse: camera.request(LunaProtocol.captureStatusRequest))))")
    }
    try remember(try allURIs(camera).subtracting(before))
}

func runDelete(_ camera: Camera, uri: String) throws {
    let created = Set(((try? String(contentsOf: createdList, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
    // Safety: never delete anything this tool did not create in a recorded run.
    guard created.contains(uri) else { throw ProbeError("refusing: \(uri) is not in \(createdList.path)") }
    guard try allURIs(camera).contains(uri) else { throw ProbeError("\(uri) not on camera") }
    let reply = try camera.send(LunaProtocol.deleteFiles(uri))
    log("delete reply \(reply.code) raw=\(hex(reply.body))")
    Thread.sleep(forTimeInterval: 1)
    log("still present after delete: \(try allURIs(camera).contains(uri))")
}

func runStatus(_ camera: Camera) throws {
    let status = try camera.request(LunaProtocol.statusRequest())
    print("STATUS \(describe(try LunaDeviceStatus(response: status)))\n  raw=\(nested(status))")
    let storage = try camera.request(LunaProtocol.storageListRequest())
    print("STORAGE \(describe(try LunaDeviceStatus(response: storage)))\n  raw=\(nested(storage))")
    let mode = try camera.request(LunaProtocol.shootingModeRequest())
    let modeStatus = try LunaDeviceStatus(response: mode)
    print("MODE \(modeStatus.shootingMode.map { "\($0)" } ?? "?") raw=\(nested(mode))")
    for bank: UInt32 in [modeStatus.shootingMode?.functionMode.rawValue ?? 7, 7] {
        let remaining = try camera.request(LunaProtocol.remainingTimeRequest(functionMode: bank))
        print("REMAINING fm=\(bank) \(describe(try LunaPhotographySettings(response: remaining).remainingRecordTime)) raw=\(nested(remaining))")
    }
    let capture = try camera.request(LunaProtocol.captureStatusRequest)
    print("CAPTURE \(describe(try LunaCaptureStatus(captureStatusResponse: capture))) raw=\(dump(capture))")
    if let body = try? camera.request(LunaProtocol.darkEISStatusRequest) {
        print("DARK_EIS \(try LunaProtocol.darkEISStatus(response: body)) raw=\(dump(body))")
    }
    if let body = try? camera.request(LunaProtocol.timelapseOptionsRequest) {
        print("TIMELAPSE \(try LunaProtocol.timelapseOptions(response: body)) raw=\(dump(body))")
    }
}

func run() throws {
    if command == "help" || command == "-h" { print(usage); return }
    let camera = try connect()
    defer { camera.close() }
    let info = camera.info!
    log("connected \(info.model) fw \(info.firmware) serial ...\(info.serial.map { String($0.suffix(4)) } ?? "?")")
    switch command {
    case "info":
        print("INFO model=\(info.model) firmware=\(info.firmware) serialSuffix=\(info.serial.map { String($0.suffix(4)) } ?? "?")")
    case "status":
        try runStatus(camera)
    case "get":
        let types = rest.first.map { $0.split(separator: ",").compactMap { UInt32($0) } }
            ?? LunaPhotographyType.allCases.map(\.rawValue)
        let modes = functionModeOverride.map { [$0] } ?? LunaFunctionMode.allCases.map(\.rawValue)
        for mode in modes {
            let reply = try camera.send(LunaProtocol.getPhotographyOptions(types, mode: mode))
            guard reply.code == 200 else { print("GET fm=\(mode) rejected \(reply.code)"); continue }
            let settings = try LunaPhotographySettings(response: reply.body)
            print("GET fm=\(mode) \(describe(settings))")
            print("  raw=\(nested(reply.body))")
        }
    case "set":
        try runSet(camera)
    case "live":
        try runLive(camera, seconds: number(0, "seconds"), out: rest.count > 1 ? rest[1] : nil)
    case "notify":
        Thread.sleep(forTimeInterval: try number(0, "seconds"))
    case "files":
        let files = try mediaFiles(camera)
        for file in files { print("FILE \(file.uri) \(describe(file.metadata as Any))") }
        let list = try LunaProtocol.fileList(response: camera.request(LunaProtocol.fileListRequest()))
        print("cmd38 files=\(files.count) cmd13 uris=\(list.uris.count) total=\(list.totalCount)")
        for uri in list.uris where !files.contains(where: { $0.uri == uri }) { print("CMD13-ONLY \(uri)") }
    case "thumb":
        guard rest.count >= 2 else { throw ProbeError("thumb <uri> <out.png>") }
        let body = try camera.request(LunaProtocol.fileExtraRequest(rest[0], extraType: .thumbnail), timeout: 20)
        let thumbnail = try LunaThumbnail(response: body)
        try writePNG(thumbnail, to: URL(fileURLWithPath: rest[1]))
        print("THUMB \(thumbnail.width)x\(thumbnail.height) bytes=\(body.count) header=\(hex(body.prefix(40))) -> \(rest[1])")
        let meta = try camera.request(LunaProtocol.fileExtraRequest(rest[0], extraType: .metadata))
        print("META \(describe(try LunaFileMetadata(meta)))")
    case "record":
        try runRecord(camera, seconds: number(0, "seconds"))
    case "photo":
        try runPhoto(camera)
    case "delete":
        guard let uri = rest.first else { throw ProbeError("delete <uri>") }
        try runDelete(camera, uri: uri)
    case "http":
        // Sends cmd 118 access state (default 1) inside the session, then a Range GET.
        guard let uri = rest.first else { throw ProbeError("http <uri> [state] [range] [out]") }
        let state = UInt64(rest.count > 1 ? rest[1] : "1") ?? 1
        if state > 0 {
            let reply = try camera.send(LunaProtocol.setAccessCameraFileState(state))
            log("cmd 118 state \(state) reply \(reply.code) raw=\(hex(reply.body))")
        }
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-s", "--interface", "en0", "-r", rest.count > 2 ? rest[2] : "0-1023", "-D", "-",
                          "-o", rest.count > 3 ? rest[3] : "/dev/null", "http://\(LunaProtocol.defaultHost)\(uri)"]
        try curl.run()
        curl.waitUntilExit()
    case "raw":
        guard let code = UInt16(rest.first ?? "") else { throw ProbeError("raw <code> <hexbody>") }
        let reply = try camera.send(LunaRequest(code: code, body: unhex(rest.count > 1 ? rest[1] : "")))
        print("RAW reply \(reply.code) bytes=\(reply.body.count) hex=\(hex(reply.body.prefix(512)))\n  \(dump(reply.body))")
    default:
        print(usage)
    }
    Thread.sleep(forTimeInterval: 0.2)
}

do {
    try run()
} catch {
    print("ERROR \(error)")
    exit(1)
}

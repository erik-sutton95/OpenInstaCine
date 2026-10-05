import Foundation
import OpenPocketViewCore

/// Darwin-safe wire helpers used by the Android JNI shims. Compiles on macOS
/// so `swift test` still sees a real facade target; JNI itself stays
/// `#if os(Android)` in `SwiftCoreJNI.swift`.
public enum AndroidSessionWire {
    public static var coreVersion: String {
        #if arch(arm64)
            let arch = "arm64"
        #elseif arch(x86_64)
            let arch = "x86_64"
        #else
            let arch = "unknown"
        #endif
        return "OpenPocketViewCore swift-android/\(arch)"
    }

    public static func statusJSON(_ status: CameraStatus) -> String {
        func bool(_ v: Bool) -> String { v ? "true" : "false" }
        func quote(_ s: String?) -> String {
            guard let s else { return "null" }
            let escaped =
                s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        let blob = status.audioDspBlob.flatMap { $0.isEmpty ? nil : hex($0) }
        func ints(_ xs: [Int]) -> String {
            "[\(xs.map(String.init).joined(separator: ","))]"
        }
        let isoCaps = status.availableIsoIndices.map { Int($0.rawValue) }
        let colorCaps = status.availableColorModes.map { Int($0.rawValue) }
        let formatCaps = status.availableVideoFormats.flatMap {
            [Int($0.resolution.rawValue), Int($0.frameRate.rawValue)]
        }
        let zoomFactorJSON = status.zoomFactor.map { String($0) } ?? "null"
        let glamourJSON = status.glamourEnabled.map { bool($0) } ?? "null"
        let selfieFlipJSON = status.selfieFlip.map { bool($0.isOn) } ?? "null"
        return """
            {"batteryPercent":\(status.batteryPercent),"batteryMilliVolts":\(status.batteryMilliVolts),"batteryMilliAmps":\(status.batteryMilliAmps),"docked":\(bool(status.docked)),"charging":\(bool(status.charging)),"storageTotalMb":\(status.storageTotalMb),"storageFreeMb":\(status.storageFreeMb),"sdTotalMb":\(status.sdTotalMb),"sdFreeMb":\(status.sdFreeMb),"internalTotalMb":\(status.internalTotalMb),"internalFreeMb":\(status.internalFreeMb),"inPlayback":\(bool(status.inPlayback)),"firmware":\(quote(status.firmware)),"isRecording":\(bool(status.isRecording)),"shootingMode":\(status.shootingMode),"recordElapsedSec":\(status.recordElapsedSec),"recordRemainingSec":\(status.recordRemainingSec),"timecode":\(quote(status.timecode)),"iso":\(status.iso),"shutterDenom":\(status.shutterDenom),"fps":\(status.fps),"expoMode":\(intOrMinus(status.expoMode?.rawValue)),"isoIndex":\(intOrMinus(status.isoIndex?.rawValue)),"colorMode":\(intOrMinus(status.colorMode?.rawValue)),"videoResolution":\(intOrMinus(status.videoResolution?.rawValue)),"fpsIndex":\(intOrMinus(status.videoFormat?.frameRate.rawValue)),"whiteBalanceMode":\(intOrMinus(status.whiteBalance?.mode.rawValue)),"whiteBalanceKelvin":\(status.whiteBalanceKelvin),"whiteBalanceTint":\(status.whiteBalanceTint ?? 0),"autoWhiteBalanceKelvin":\(status.autoWhiteBalanceKelvin),"focusMode":\(intOrMinus(status.focusMode?.rawValue)),"audioChannel":\(intOrMinus(status.audioChannel?.rawValue)),"vocalBoost":\(intOrMinus(status.vocalBoost?.rawValue)),"audioDspAt2":\(intOrMinus(status.audioDspAt2?.rawValue)),"audioDspBlob":\(quote(blob)),"zoomFactorRaw":\(status.zoomFactorRaw),"availableShutterDenoms":\(ints(status.availableShutterDenoms)),"availableIsoIndices":\(ints(isoCaps)),"evComp":\(intOrMinus(status.evComp?.rawValue)),"meteredEv":\(intOrMinus(status.meteredEv?.rawValue)),"isoLimit":\(intOrMinus(status.isoLimit?.rawValue)),"availableColorModes":\(ints(colorCaps)),"availableVideoFormats":\(ints(formatCaps)),"focusX":\(status.focusX),"focusY":\(status.focusY),"hasCameraFocusPoint":\(bool(status.hasCameraFocusPoint)),"focusTrack":\(intOrMinus(status.focusTrack?.rawValue)),"zoomLens":\(intOrMinus(status.zoomLens)),"zoomFactor":\(zoomFactorJSON),"glamourEnabled":\(glamourJSON),"selfieFlip":\(selfieFlipJSON),"gimbalFace":\(intOrMinus(status.gimbalFace?.rawValue)),"gimbalModeFamily":\(intOrMinus(status.gimbalModeFamily?.rawValue)),"windNR":\(intOrMinus(status.windNR?.rawValue)),"directionalAudio":\(intOrMinus(status.directionalAudio?.rawValue)),"audioMetersLeft":\(status.audioMeters.left.levelDB),"audioMetersRight":\(status.audioMeters.right.levelDB),"audioPeakLeft":\(status.audioMeters.left.peakDB),"audioPeakRight":\(status.audioMeters.right.peakDB)}
            """
    }

    /// Probe + labels for playback conform preview. Request keys: `nominalFrameRate`,
    /// `minFrameDurationSeconds`, `listedRate`, optional `targetRate` / `sourceSeconds`.
    public static func conformPreviewJSON(_ request: String) -> String {
        let source = ConformPreview.probe(
            nominalFrameRate: jsonOptionalNumber(request, key: "nominalFrameRate"),
            minFrameDurationSeconds: jsonOptionalNumber(request, key: "minFrameDurationSeconds"),
            listedRate: jsonOptionalNumber(request, key: "listedRate"))
        let availability = ConformPreview.availability(for: source)
        var dict: [String: Any] = [
            "isVariableFrameRate": source.isVariableFrameRate,
            "isAlreadyConformed": source.isAlreadyConformed,
            "audioLabel": ConformPreview.audioLabel,
            "conformFloor": NSNumber(value: ConformPreview.conformFloor),
            "targetRates": ConformPreview.targetRates.map { NSNumber(value: $0) },
            "availability": availabilityName(availability),
            "targets": availability.targets.map { NSNumber(value: $0) },
        ]
        if let reason = availability.unavailableReason {
            dict["unavailableReason"] = reason
        }
        if let capture = source.captureRate {
            dict["captureRate"] = NSNumber(value: capture)
            dict["menuHeader"] = ConformPreview.menuHeader(captureRate: capture)
            dict["rateLabel"] = ConformPreview.rateLabel(capture)
            dict["targetLabels"] = availability.targets.map {
                ConformPreview.targetLabel(captureRate: capture, targetRate: $0)
            }
            if let target = jsonOptionalNumber(request, key: "targetRate") {
                let speed = ConformPreview.speed(captureRate: capture, targetRate: target)
                dict["speed"] = NSNumber(value: speed)
                dict["targetLabel"] = ConformPreview.targetLabel(
                    captureRate: capture, targetRate: target)
                dict["label"] = ConformPreview.label(captureRate: capture, targetRate: target)
                if let seconds = jsonOptionalNumber(request, key: "sourceSeconds") {
                    dict["conformedDuration"] = NSNumber(
                        value: ConformPreview.conformedDuration(
                            sourceSeconds: seconds, speed: speed))
                }
            }
        }
        guard JSONSerialization.isValidJSONObject(dict),
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// Android JNI: `CameraSoftAP` decisions so Kotlin does not clone the ladder.
    /// `kind` is the function name. Bool results are `true` / `false`. Enums use
    /// `HandshakeTimeoutStep` / `FirstPictureStep` raw values.
    public static func cameraSoftAPDecision(kind: String, requestJSON: String) -> String {
        let json = requestJSON
        func flag(_ value: Bool) -> String { value ? "true" : "false" }
        switch kind {
        case "handshakeTimeoutStep":
            return CameraSoftAP.handshakeTimeoutStep(
                pathReady: jsonBool(json, key: "pathReady", default: false),
                rebindsUsed: Int(jsonNumber(json, key: "rebindsUsed", default: 0)),
                inboundDatagrams: Int(jsonNumber(json, key: "inboundDatagrams", default: 0)),
                rebindLimit: Int(
                    jsonNumber(
                        json, key: "rebindLimit",
                        default: Double(CameraSoftAP.handshakeRebindLimit)))
            ).rawValue
        case "firstPictureStep":
            return CameraSoftAP.firstPictureStep(
                videoPackets: Int(jsonNumber(json, key: "videoPackets", default: 0)),
                enableSends: Int(jsonNumber(json, key: "enableSends", default: 0)),
                secondsSinceLastEnable: jsonNumber(
                    json, key: "secondsSinceLastEnable", default: 0),
                secondsSinceLastVideo: jsonOptionalNumber(json, key: "secondsSinceLastVideo"),
                secondsSinceLastRebuild: jsonOptionalNumber(json, key: "secondsSinceLastRebuild"),
                secondsSinceLastStatus: jsonOptionalNumber(json, key: "secondsSinceLastStatus"),
                needsRecordingFormatPoke: jsonBool(
                    json, key: "needsRecordingFormatPoke", default: false),
                alreadyPokedRecordingFormat: jsonBool(
                    json, key: "alreadyPokedRecordingFormat", default: false),
                recordingFormatPokeInFlight: jsonBool(
                    json, key: "recordingFormatPokeInFlight", default: false),
                isRecording: jsonBool(json, key: "isRecording", default: false),
                hasPresentedPicture: jsonBool(json, key: "hasPresentedPicture", default: false)
            ).rawValue
        case "shouldKickAfterHandshakeTimeout":
            return flag(
                CameraSoftAP.shouldKickAfterHandshakeTimeout(
                    pathReady: jsonBool(json, key: "pathReady", default: false)))
        case "shouldGiveUpOpenRetry":
            return flag(
                CameraSoftAP.shouldGiveUpOpenRetry(
                    attempts: Int(jsonNumber(json, key: "attempts", default: 0))))
        case "canSendHandshake":
            return flag(
                CameraSoftAP.canSendHandshake(
                    receiveArmed: jsonBool(json, key: "receiveArmed", default: false),
                    connectionReady: jsonBool(json, key: "connectionReady", default: false)))
        case "shouldRecoverAfterForeground":
            return flag(
                CameraSoftAP.shouldRecoverAfterForeground(
                    secondsSinceLastPresented: jsonOptionalNumber(
                        json, key: "secondsSinceLastPresented"),
                    videoFresh: jsonBool(json, key: "videoFresh", default: false),
                    statusFresh: jsonBool(json, key: "statusFresh", default: false)))
        case "shouldEscalateForegroundRecover":
            return flag(
                CameraSoftAP.shouldEscalateForegroundRecover(
                    secondsSinceLastPresented: jsonOptionalNumber(
                        json, key: "secondsSinceLastPresented"),
                    videoFresh: jsonBool(json, key: "videoFresh", default: false),
                    statusFresh: jsonBool(json, key: "statusFresh", default: false)))
        case "shouldKeepaliveRebuildUDP":
            return flag(
                CameraSoftAP.shouldKeepaliveRebuildUDP(
                    flowNeedsRebuild: jsonBool(json, key: "flowNeedsRebuild", default: false),
                    rebuildInFlight: jsonBool(json, key: "rebuildInFlight", default: false),
                    secondsSinceLastRebuild: jsonOptionalNumber(
                        json, key: "secondsSinceLastRebuild"),
                    videoFresh: jsonBool(json, key: "videoFresh", default: false),
                    sawPicture: jsonBool(json, key: "sawPicture", default: true),
                    statusFresh: jsonBool(json, key: "statusFresh", default: false),
                    secondsSinceLastEnable: jsonOptionalNumber(
                        json, key: "secondsSinceLastEnable"),
                    pathReady: jsonBool(json, key: "pathReady", default: true)))
        case "shouldRebuildAfterCommandTimeouts":
            return flag(
                CameraSoftAP.shouldRebuildAfterCommandTimeouts(
                    timeoutsInWindow: Int(jsonNumber(json, key: "timeoutsInWindow", default: 0)),
                    downlinkFresh: jsonBool(json, key: "downlinkFresh", default: false),
                    videoFresh: jsonBool(json, key: "videoFresh", default: false),
                    rebuildInFlight: jsonBool(json, key: "rebuildInFlight", default: false),
                    secondsSinceLastRebuild: jsonOptionalNumber(
                        json, key: "secondsSinceLastRebuild"),
                    statusFresh: jsonBool(json, key: "statusFresh", default: false)))
        case "shouldForceEnableAfterUDPRebuild":
            return flag(
                CameraSoftAP.shouldForceEnableAfterUDPRebuild(
                    hadVideo: jsonBool(json, key: "hadVideo", default: false)))
        case "shouldRearmLiveIngestAfterUDPRebuild":
            return flag(
                CameraSoftAP.shouldRearmLiveIngestAfterUDPRebuild(
                    wasAccepting: jsonBool(json, key: "wasAccepting", default: false)))
        case "shouldBeginIDRHoldOnEnable":
            return flag(
                CameraSoftAP.shouldBeginIDRHoldOnEnable(
                    hasPresentedPicture: jsonBool(
                        json, key: "hasPresentedPicture", default: false)))
        case "shouldRunFirstPictureRecover":
            return flag(
                CameraSoftAP.shouldRunFirstPictureRecover(
                    secondsSinceLastPresented: jsonOptionalNumber(
                        json, key: "secondsSinceLastPresented"),
                    alreadySettled: jsonBool(json, key: "alreadySettled", default: false)))
        case "shouldMarkFirstPictureSettled":
            return flag(
                CameraSoftAP.shouldMarkFirstPictureSettled(
                    secondsSinceLastPresented: jsonOptionalNumber(
                        json, key: "secondsSinceLastPresented"),
                    secondsSinceLastEnable: jsonNumber(
                        json, key: "secondsSinceLastEnable", default: 0)))
        case "shouldDeferRecordingFormatPoke":
            return flag(
                CameraSoftAP.shouldDeferRecordingFormatPoke(
                    hasKnownRecordingFormat: jsonBool(
                        json, key: "hasKnownRecordingFormat", default: false),
                    secondsSinceLastEnable: jsonNumber(
                        json, key: "secondsSinceLastEnable", default: 0)))
        case "shouldContinueFirstPictureAfterStrayPlayback":
            return flag(
                CameraSoftAP.shouldContinueFirstPictureAfterStrayPlayback(
                    hasPicture: jsonBool(json, key: "hasPicture", default: false)))
        case "shouldClearForegroundRecoverWithoutRebuild":
            return flag(
                CameraSoftAP.shouldClearForegroundRecoverWithoutRebuild(
                    holdsMonitor: jsonBool(json, key: "holdsMonitor", default: false)))
        case "shouldExitPlaybackBeforeLiveEnable":
            return flag(
                CameraSoftAP.shouldExitPlaybackBeforeLiveEnable(
                    inPlayback: jsonBool(json, key: "inPlayback", default: false)))
        case "shouldSendLiveViewPrepare":
            return flag(
                CameraSoftAP.shouldSendLiveViewPrepare(
                    usesNanoLiveViewGate: jsonBool(
                        json, key: "usesNanoLiveViewGate", default: false)))
        case "shouldPokeRecordingFormat":
            return flag(
                CameraSoftAP.shouldPokeRecordingFormat(
                    needsPoke: jsonBool(json, key: "needsPoke", default: false),
                    alreadyPoked: jsonBool(json, key: "alreadyPoked", default: false),
                    isRecording: jsonBool(json, key: "isRecording", default: false),
                    hadVideo: jsonBool(json, key: "hadVideo", default: false),
                    enableSends: Int(jsonNumber(json, key: "enableSends", default: 0)),
                    secondsSinceLastEnable: jsonNumber(
                        json, key: "secondsSinceLastEnable", default: 0)))
        case "shouldSendLiveViewEnableAfterHandshake":
            return flag(
                CameraSoftAP.shouldSendLiveViewEnableAfterHandshake(
                    alreadySent: jsonBool(json, key: "alreadySent", default: false)))
        case "shouldReuseDatalink":
            return flag(
                CameraSoftAP.shouldReuseDatalink(
                    isClosed: jsonBool(json, key: "isClosed", default: false)))
        case "shouldCommitLiveHandshake":
            return flag(
                CameraSoftAP.shouldCommitLiveHandshake(
                    driverOwned: jsonBool(json, key: "driverOwned", default: false),
                    isClosed: jsonBool(json, key: "isClosed", default: false),
                    isCancelled: jsonBool(json, key: "isCancelled", default: false)))
        case "shouldHoldForGOPReset":
            return flag(
                FeedWatchdog.shouldHoldForGOPReset(
                    secondsSinceLastEnable: jsonOptionalNumber(
                        json, key: "secondsSinceLastEnable"),
                    lastVideoPacketAge: jsonOptionalNumber(json, key: "lastVideoPacketAge")))
        case "decoderRepairStep":
            return FeedWatchdog.decoderRepairStep(
                secondsSinceRepairStart: jsonNumber(
                    json, key: "secondsSinceRepairStart", default: 0),
                secondsSinceLastEnable: jsonNumber(json, key: "secondsSinceLastEnable", default: 0),
                secondsSinceLastIrap: jsonOptionalNumber(json, key: "secondsSinceLastIrap"),
                keyframeRequests: Int(jsonNumber(json, key: "keyframeRequests", default: 0))
            ).rawValue
        case "nextSessionHoldCycles":
            return String(
                FeedWatchdog.nextSessionHoldCycles(
                    lastVideoPacketAge: jsonOptionalNumber(json, key: "lastVideoPacketAge"),
                    previousCycles: Int(jsonNumber(json, key: "previousCycles", default: 0)),
                    pictureSinceLastCycle: jsonBool(
                        json, key: "pictureSinceLastCycle", default: false)))
        case "shouldStartFeedRecovery":
            return flag(
                FeedWatchdog.shouldStartFeedRecovery(
                    rebuildInFlight: jsonBool(json, key: "rebuildInFlight", default: false)))
        case "shouldSendRecoverEnable":
            return flag(
                FeedWatchdog.shouldSendRecoverEnable(
                    pathReady: jsonBool(json, key: "pathReady", default: false),
                    decoderReady: jsonBool(json, key: "decoderReady", default: false)))
        case "shouldTreatLiveVideoAsStale":
            return flag(
                FeedWatchdog.shouldTreatLiveVideoAsStale(
                    lastVideoPacketAge: jsonOptionalNumber(json, key: "lastVideoPacketAge"),
                    hadVideo: jsonBool(json, key: "hadVideo", default: false),
                    recovering: jsonBool(json, key: "recovering", default: false)))
        case "shouldRepeatRecoverEnable":
            return flag(
                FeedWatchdog.shouldRepeatRecoverEnable(
                    secondsSinceLastEnable: jsonNumber(
                        json, key: "secondsSinceLastEnable", default: 0),
                    secondsSinceLastRebuild: jsonOptionalNumber(
                        json, key: "secondsSinceLastRebuild"),
                    pathReady: jsonBool(json, key: "pathReady", default: true),
                    lastBleNotifyAge: jsonOptionalNumber(json, key: "lastBleNotifyAge"),
                    hadVideo: jsonBool(json, key: "hadVideo", default: true)))
        default:
            return ""
        }
    }

    private static func intOrMinus<T: BinaryInteger>(_ value: T?) -> Int {
        guard let value else { return -1 }
        return Int(value)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func availabilityName(_ availability: ConformPreview.Availability) -> String {
        switch availability {
        case .available: "available"
        case .unknownRate: "unknownRate"
        case .variableRate: "variableRate"
        case .alreadyConformed: "alreadyConformed"
        case .notHighFrameRate: "notHighFrameRate"
        }
    }

    private static func jsonBool(_ json: String, key: String, default def: Bool) -> Bool {
        if json.contains("\"\(key)\":true") { return true }
        if json.contains("\"\(key)\":false") { return false }
        return def
    }

    private static func jsonOptionalNumber(_ json: String, key: String) -> Double? {
        guard let range = json.range(of: "\"\(key)\":") else { return nil }
        var s = ""
        var started = false
        for ch in json[range.upperBound...] {
            if ch.isWhitespace && !started { continue }
            if !started && ch == "n" { return nil }
            started = true
            if ch == "-" && s.isEmpty {
                s.append(ch)
                continue
            }
            if ch.isNumber || ch == "." || ch == "e" || ch == "E" || ch == "+" {
                s.append(ch)
            } else {
                break
            }
        }
        return Double(s)
    }

    private static func jsonNumber(_ json: String, key: String, default def: Double) -> Double {
        jsonOptionalNumber(json, key: key) ?? def
    }

    // Same semantics over a `flatJSONFields` index, for payloads read field by field.
    private static func jsonBool(_ fields: [String: Substring], key: String, default def: Bool)
        -> Bool
    {
        guard let v = fields[key] else { return def }
        if v.hasPrefix("true") { return true }
        if v.hasPrefix("false") { return false }
        return def
    }

    private static func jsonOptionalNumber(_ fields: [String: Substring], key: String) -> Double? {
        guard let v = fields[key]?.drop(while: \.isWhitespace), v.first != "n" else { return nil }
        let body = v.hasPrefix("-") ? v.dropFirst() : v
        let digits = body.prefix(while: { $0.isNumber || ".eE+".contains($0) })
        return Double(v[v.startIndex..<digits.endIndex])
    }

    private static func jsonNumber(
        _ fields: [String: Substring], key: String, default def: Double
    ) -> Double {
        jsonOptionalNumber(fields, key: key) ?? def
    }

    /// String value from Kotlin `JSONObject`; parsing undoes `quote` escapes such as `\/`.
    private static func jsonString(_ json: String, key: String) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return (object as? [String: Any])?[key] as? String
    }
}

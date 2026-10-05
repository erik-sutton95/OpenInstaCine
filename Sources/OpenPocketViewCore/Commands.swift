import Foundation

/// Builders for the DUML frames of the connection spine, ported byte-for-byte from Osmosis
/// (`duml/OsmoCommands.kt`, `camera/CameraSession.kt`). BLE frames carry a message id in `seq`;
/// datalink frames carry the running `dumlSeq` there (the DatalinkDriver assigns it).
public enum Commands {
    static func rx(type: UInt8, id: UInt8) -> UInt8 { (id << 5) | type }

    // ---- BLE session sequence (written to fff5, paced) ----------------------------------------

    // ---- Datalink registration (seq = dumlSeq, assigned by the driver) -------------------------

    /// `0x00/0x28` delete. Osmosis: `[count][handles][counter:u32] 00 [count:u32] 01 01 00 00`.
    public static func deleteMedia(handle: UInt32, counter: UInt32, seq: UInt16 = 0) -> Duml.Frame {
        var payload: [UInt8] = [0x01]
        payload += le32(handle)
        payload += le32(counter)
        payload += [0x00]
        payload += le32(1)
        payload += [0x01, 0x01, 0x00, 0x00]
        return Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x28, payload: payload)
    }

    // ---- Camera control (Osmosis §10–14, App → Camera `0x01`, flags `0x40`) ---------------------

    /// `0x02/0xE1` shooting mode. Only send tabled `ShootingMode` values — do not enumerate.
    /// Photo is body-specific: Pocket 3 / Nano `0x05`, Pocket 4 / 4 Pro `0x17`. `model: nil`
    /// keeps the historic Photo `0x17` payload.
    public static func setShootingMode(
        _ mode: ShootingMode, model: CameraModel? = nil, seq: UInt16 = 0
    ) -> Duml.Frame {
        camera(0xE1, [mode.wireByte(for: model)], seq: seq)
    }

    /// `0x02/0xE1` from a raw wire value, for callers that carry the byte rather than the case —
    /// Photo is body-dependent (`0x17` on a Pocket 4, `0x05` on a Pocket 3 / Nano), and only one
    /// of those can be `ShootingMode.photo`.
    ///
    /// Returns nil for anything outside `ShootingMode.tabledRawValues`. That refusal is the point:
    /// sweeping this opcode's value space froze a Nano solid and needed a power cycle, so an
    /// unrecognised mode must never reach the wire.
    public static func setShootingMode(raw: UInt8, seq: UInt16 = 0) -> Duml.Frame? {
        guard ShootingMode.tabledRawValues.contains(raw) else { return nil }
        return camera(0xE1, [raw], seq: seq)
    }

    /// `0x02/0x8E` SET = `01 01 <pid:u16-LE> <len:u8> <value…>`.
    public static func paramSet(_ param: CameraParam, value: [UInt8], seq: UInt16 = 0) -> Duml.Frame
    {
        let pid = param.rawValue
        var p: [UInt8] = [0x01, 0x01, UInt8(pid & 0xFF), UInt8(pid >> 8), UInt8(value.count)]
        p += value
        return camera(0x8E, p, seq: seq)
    }

    public static func setIsoLimit(_ limit: IsoLimit, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.isoLimit, value: [limit.rawValue], seq: seq)
    }

    /// `0x02/0x2E` 1-byte EV. mimo-settings-1 while Auto, ACK `00`:
    /// `10` (pkt 53846), `11`, `12`, `0f`. Echoes `cam_expo_param` `@6`. `0x10` = 0.0.
    public static func setEv(_ ev: EvComp, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x2E, [ev.rawValue], seq: seq)
    }

    public static func setFov(_ fov: FovSetting, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.fov, value: [fov.rawValue], seq: seq)
    }

    /// `0x02/0x42` color. Pocket 4 uses `ColorMode.rawValue`; Pocket 3 and Nano
    /// use `wireByte(for:)` (Pocket 3 `00` Normal / `3C` HDR / `3D` D-Log M;
    /// Nano `00` Normal 8-bit / `3F` Normal 10-bit / `3D` D-Log M).
    public static func setColorMode(
        _ mode: ColorMode, model: CameraModel? = nil, seq: UInt16 = 0
    ) -> Duml.Frame {
        camera(0x42, [mode.wireByte(for: model)], seq: seq)
    }

    /// `0x02/0x24` focus. Single `01`, Continuous `02`.
    public static func setFocusMode(_ mode: FocusMode, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x24, [mode.rawValue], seq: seq)
    }

    /// SET `01 01 3B 00 02 01 <mode>`. Default `00`, Showcase `01`, Lock `02`, Priority `03`.
    public static func setFocusTrack(_ mode: FocusTrackMode, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.focusTrack, value: mode.setValue, seq: seq)
    }

    /// `0x02/0x2C` white balance. 5 B `[mode][K/100 u16-LE][tint i16-LE]`.
    /// Auto is kelvin 0 and keeps `tint` (Mimo `00 00 00 14 00` at tint 20).
    public static func setWhiteBalance(_ wb: WhiteBalance, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x2C, wb.setPayload, seq: seq)
    }

    public static func setWhiteBalanceAuto(tint: Int = 0, seq: UInt16 = 0) -> Duml.Frame {
        setWhiteBalance(.auto(tint: tint), seq: seq)
    }

    public static func setWhiteBalanceCustom(kelvin: Int, tint: Int, seq: UInt16 = 0) -> Duml.Frame
    {
        setWhiteBalance(.custom(kelvin: kelvin, tint: tint), seq: seq)
    }

    /// SET `01 01 20 00 01 <v>`. Stereo `02`, Mono `01`, Spatial `03`.
    public static func setAudioChannel(_ channel: AudioChannel, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.audioChannel, value: [channel.rawValue], seq: seq)
    }

    /// SET `01 01 4C 00 01 <v>`. Off `00`, On `01`.
    public static func setVocalBoost(_ boost: VocalBoost, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.vocalBoost, value: [boost.rawValue], seq: seq)
    }

    /// `0x02/0x18` res+fps. 5 B `[res][fps_idx] 00 00 00`. No GET.
    public static func setVideoFormat(
        _ format: VideoFormat, shootingMode: ShootingMode? = nil, seq: UInt16 = 0
    ) -> Duml.Frame {
        camera(0x18, format.setPayload(shootingMode: shootingMode), seq: seq)
    }

    public static func setVideoFormat(
        resolution: VideoResolution, frameRate: VideoFrameRate,
        shootingMode: ShootingMode? = nil, seq: UInt16 = 0
    ) -> Duml.Frame {
        setVideoFormat(
            VideoFormat(resolution: resolution, frameRate: frameRate),
            shootingMode: shootingMode, seq: seq)
    }

    /// `0x02/0xb8` slider SET. `0A 4E` + u16-LE lens `@14` (217 = 1×, 651 = 3×,
    /// 2604 = 12×). Mimo pinch is this form at 50 ms for the whole range.
    public static func setZoomLens(_ position: UInt16, seq: UInt16 = 0) -> Duml.Frame {
        camera(0xB8, [0x0A, 0x4E, UInt8(position & 0xFF), UInt8(position >> 8)], seq: seq)
    }

    /// Factor → slider SET (`0A 4E` + inverse-focal lens). Chip 12× is a slew.
    public static func setZoom(factor: Double, seq: UInt16 = 0) -> Duml.Frame {
        setZoomLens(CamFov.lensPosition(for: factor), seq: seq)
    }

    /// `0x02/0xb8` `03 00` + u16-LE. 100 (`64 00`) slews toward 12×; 300
    /// (`2C 01`) from 12× lands at 9.15×. ACK `00`.
    public static func setZoomSlew(_ value: UInt16, seq: UInt16 = 0) -> Duml.Frame {
        camera(0xB8, [0x03, 0x00, UInt8(value & 0xFF), UInt8(value >> 8)], seq: seq)
    }

    /// `0x02/0xb8` `FF 00 00 00` — stop after a `03 00` slew on older firmware.
    public static func setZoomStop(seq: UInt16 = 0) -> Duml.Frame {
        camera(0xB8, [0xFF, 0x00, 0x00, 0x00], seq: seq)
    }

    // ---- Gimbal (`rcv=0x04`). Flip/mode/speed ACK flags `0x80`; stick flags `0x00`, no ACK. ----

    /// `0x04/0x01` flags `0x00`, 10 B, no ACK. Axes u16-LE @0/@4, center 1024 ±550, trailer `00 80 22 00`.
    public static func gimbalStick(axis0: UInt16, axis1: UInt16, seq: UInt16 = 0) -> Duml.Frame {
        var p = le16(Int(axis0))
        p += [0x00, 0x00]
        p += le16(Int(axis1))
        p += [0x00, 0x80, 0x22, 0x00]
        return gimbal(0x01, p, seq: seq, flags: Duml.flagNotify)
    }

    /// Native angle command: yaw/roll/pitch i16-LE tenths, mode, time in
    /// tenths. Mode 0x05 = absolute, roll ignored. Pocket look-up pitch is
    /// distinct from native absolute pitch at attitude i16 @0. Uses notify.
    public static func gimbalTimedTarget(
        yawDeg: Double, nativePitchDeg: Double, duration: TimeInterval, seq: UInt16 = 0
    ) -> Duml.Frame? {
        guard yawDeg.isFinite, nativePitchDeg.isFinite, duration.isFinite,
            (HeadTrack.Reach.panMinDeg...HeadTrack.Reach.panMaxDeg).contains(yawDeg),
            (-180...180).contains(nativePitchDeg),
            duration >= 0.1, duration <= 25.5,
            abs(duration * 10 - (duration * 10).rounded()) < 1e-6
        else { return nil }
        let payload = le16(Int((yawDeg * 10).rounded())) + [0, 0]
            + le16(Int((nativePitchDeg * 10).rounded())) + [0x05, UInt8((duration * 10).rounded())]
        return gimbal(0x14, payload, seq: seq, flags: Duml.flagNotify)
    }

    /// Validate physical display tilt before encoding the distinct native pitch.
    public static func gimbalTimedTarget(
        waypoint: GimbalWaypoint, duration: TimeInterval, seq: UInt16 = 0
    ) -> Duml.Frame? {
        guard waypoint.pitchDeg.isFinite,
            (HeadTrack.Reach.tiltMinDeg...HeadTrack.Reach.tiltMaxDeg).contains(waypoint.pitchDeg),
            let nativePitch = waypoint.nativePitchDeg else { return nil }
        return gimbalTimedTarget(yawDeg: waypoint.yawDeg, nativePitchDeg: nativePitch,
            duration: duration, seq: seq)
    }

    /// `0x04/0x50` SET `00 05 01 <speed>`.
    public static func setGimbalSpeed(_ speed: GimbalSpeed, seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x50, [0x00, 0x05, 0x01, speed.rawValue], seq: seq)
    }

    /// `0x02/0x1E` SET — `mimo-settings-1` (8 writes, all ACK `00`).
    /// Manual `04 00` (pkt 41562, 50459, 63271, 106227). Auto `01 00` (43232, 51815, 67896, 106978).
    /// No GET: zero empty `0x1E`, no `0x8E` pid tracks this. Read `cam_expo_param` `@7`.
    public static func setExpoMode(_ mode: ExpoMode, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x1E, mode.setPayload, seq: seq)
    }

    private static func camera(_ cmd: UInt8, _ payload: [UInt8], seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x02, cmdId: cmd, payload: payload)
    }

    private static func gimbal(
        _ cmd: UInt8, _ payload: [UInt8], seq: UInt16,
        flags: UInt8 = Duml.flagRequest
    ) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: rx(type: 0x04, id: 0), seq: seq,
            flags: flags, cmdSet: 0x04, cmdId: cmd, payload: payload)
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}

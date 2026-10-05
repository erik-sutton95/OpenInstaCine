package com.opencapture.openpocketcine.session

import com.opencapture.opencine.motion.GimbalWaypoint
import kotlin.math.hypot
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Documented Pocket 4 payloads only (`docs/protocol-notes.md`).
 * No invented `0xE1` values. No 1 Hz `0x09/0xa8`.
 */
object CameraCommands {
    const val RES_1080 = 0x0A
    const val RES_4K = 0x10

    const val COLOR_NORMAL = 0x3F
    const val COLOR_HDR = 0x3C
    const val COLOR_DLOG = 0x17
    const val COLOR_DLOG2 = 0x41
    /** Semantic Normal 10-bit. Nano SET is `3F`; Pocket 3 D-Log M wire is `3D`. */
    const val COLOR_NORMAL10 = 0x3D
    /** Semantic D-Log M. Nano and Pocket 3 SET is `3D`. */
    const val COLOR_DLOG_M = 0x00
    /** Insta360 I-Log: the monitor's neutral I-Log id (`MonitorTransfer.ILOG_BRIDGE_ID`), not a DJI SET byte. */
    const val COLOR_ILOG = 65_536
    /** Insta360 Dolby Vision. Not a DJI SET byte. */
    const val COLOR_DOLBY_VISION = 0xE5

    /**
     * Pocket 3 / Nano SET / `cam_image_effect` `@2`. Pocket 3 (#176): Normal
     * `00`, HDR `3C`, D-Log M `3D`. Nano: Normal 8-bit `00`, Normal 10-bit
     * `3F`, D-Log M `3D`. Action 6 is the Nano pair without `00`. Other bodies use the COLOR_* constants as wire bytes.
     */
    fun wireColorMode(mode: Int, name: String = "", family: String = ""): Int {
        if (CameraModel.looksLikeNano(name, family) || CameraModel.looksLikeAction6(name)) {
            return when (mode) {
                COLOR_NORMAL -> 0x00
                COLOR_NORMAL10 -> 0x3F
                COLOR_DLOG_M -> 0x3D
                else -> mode
            }
        }
        if (!CameraModel.looksLikePocket3(name)) return mode
        return when (mode) {
            COLOR_NORMAL -> 0x00
            COLOR_DLOG_M -> 0x3D
            else -> mode
        }
    }

    /** Inverse of [wireColorMode]. */
    fun parseColorMode(byte: Int, name: String = "", family: String = ""): Int {
        if (CameraModel.looksLikeNano(name, family) || CameraModel.looksLikeAction6(name)) {
            return when (byte) {
                0x00 -> COLOR_NORMAL
                0x3F -> COLOR_NORMAL10
                0x3D -> COLOR_DLOG_M
                else -> byte
            }
        }
        if (!CameraModel.looksLikePocket3(name)) return byte
        return when (byte) {
            0x00 -> COLOR_NORMAL
            0x3D -> COLOR_DLOG_M
            else -> byte
        }
    }

    const val EXPO_AUTO = 0x01
    const val EXPO_MANUAL = 0x04

    const val FOCUS_SINGLE = 0x01
    const val FOCUS_CONTINUOUS = 0x02

    const val WB_AUTO = 0x00
    const val WB_CUSTOM = 0x06

    const val AUDIO_MONO = 0x01
    const val AUDIO_STEREO = 0x02
    const val AUDIO_SPATIAL = 0x03

    const val WIND_ON = 0x1A
    const val WIND_OFF = 0x18
    const val DIR_ALL = 0xDA
    const val DIR_FRONT = 0x3A
    const val DIR_FRONT_BACK = 0xBA

    /** JNI extra for `CommandKind.setExpoMode`. */
    fun expoWireExtra(mode: Int): String? =
        when (mode) {
            EXPO_AUTO -> "auto"
            EXPO_MANUAL -> "manual"
            else -> null
        }

    /** iOS `CameraSession.setWhiteBalanceCustom` clamp. */
    fun clampWhiteBalanceCustom(kelvin: Int, tint: Int): Pair<Int, Int> =
        kelvin.coerceIn(2_000, 10_000) to tint.coerceIn(-100, 100)

    /**
     * D-Log2 cannot zoom. Any step off 1× hops the body to D-Log.
     * ISO star still follows `status.colorMode` after the body reports — this
     * guess must not flip the wheel marker while `@2` is still D-Log2.
     */
    fun colorModeForZoom(factor: Double, current: Int): Int? =
        CamFov.colorModeForZoom(factor, current)

    /** iOS `CamFov.shouldRestoreDLog2` — only park back at 1×, not 2.9×. */
    fun shouldRestoreDLog2(factor: Double): Boolean = CamFov.shouldRestoreDLog2(factor)

    /** Video `0x02/0x18` trailer. SlowMo uses [slowMoFormatTrailer] instead. */
    val VIDEO_FORMAT_TRAILER: ByteArray = byteArrayOf(0x00, 0x00, 0x00)

    /**
     * Pocket 3 SlowMo `0x02/0x18` trailer, or null when that fps index has no
     * documented SlowMo request. 4X (100/120) is `00 04 00`; 8X (240) is `00 08 00`.
     */
    fun slowMoFormatTrailer(fpsIndex: Int): ByteArray? =
        when (fpsIndex) {
            VideoFrameRate.FPS100.rawValue,
            VideoFrameRate.FPS120.rawValue,
            VideoFrameRate.FPS200.rawValue,
            -> byteArrayOf(0x00, 0x04, 0x00)
            VideoFrameRate.FPS240.rawValue -> byteArrayOf(0x00, 0x08, 0x00)
            else -> null
        }

    /** `[res][fps_idx]` plus Video `00 00 00` or the documented SlowMo trailer. */
    fun resolutionFps(res: Int, fpsIndex: Int, shootingMode: Int = SHOOT_VIDEO): ByteArray {
        val trailer =
            if (shootingMode == SHOOT_SLOWMO) {
                slowMoFormatTrailer(fpsIndex) ?: VIDEO_FORMAT_TRAILER
            } else {
                VIDEO_FORMAT_TRAILER
            }
        return byteArrayOf(res.toByte(), fpsIndex.toByte()) + trailer
    }

    /**
     * JNI extra for video-format SET. Third field is shooting-mode raw for
     * Pocket 3 and Pocket 4 Pro SlowMo so the facade can emit 4X/8X trailers
     * (200 fps still uses `00 04 00`). Regular Pocket 4 omits it.
     */
    fun formatCommandExtra(
        res: Int,
        fpsIndex: Int,
        shootingMode: Int = SHOOT_VIDEO,
        cameraName: String? = null,
    ): String {
        if (shootingMode == SHOOT_SLOWMO &&
            CameraModel.supportsSlowMoFormatTrailer(cameraName.orEmpty())
        ) {
            return "$res\u001f$fpsIndex\u001f$shootingMode"
        }
        return "$res\u001f$fpsIndex"
    }

    /** `0` off, `1` on, `-1` leave. Directional bytes count as on. */
    fun windFrom(raw: Int): Int =
        when (raw) {
            WIND_OFF -> 0
            WIND_ON, DIR_ALL, DIR_FRONT, DIR_FRONT_BACK -> 1
            else -> -1
        }

    /** `0` All / `1` Front / `2` Front+back / `-1` not a directional byte. */
    fun directionalFrom(raw: Int): Int =
        when (raw) {
            DIR_ALL -> 0
            DIR_FRONT -> 1
            DIR_FRONT_BACK -> 2
            else -> -1
        }

    fun audioDspHex(blob: ByteArray): String =
        buildString(blob.size * 2) {
            for (b in blob) append("%02x".format(b.toInt() and 0xFF))
        }

    fun audioChannelLabel(value: Int): String? =
        when (value) {
            AUDIO_MONO -> "Mono"
            AUDIO_STEREO -> "Stereo"
            AUDIO_SPATIAL -> "Spatial"
            else -> null
        }

    fun audioDirLabel(mode: Int): String? =
        when (mode) {
            0 -> "All"
            1 -> "Front"
            2 -> "Front+back"
            else -> null
        }

    const val SHOOT_SLOWMO = 0x00
    const val SHOOT_VIDEO = 0x01
    const val SHOOT_TIMELAPSE = 0x02
    const val SHOOT_PHOTO = 0x05
    const val SHOOT_HYPERLAPSE = 0x0A
    const val SHOOT_PHOTO_POCKET4 = 0x17
    const val SHOOT_SUPER_NIGHT = 0x28
    /** Pocket 4 Pro Live Photo, physically observed in Mimo. */
    const val SHOOT_LIVE_PHOTO = 0x4D

    /** Still capture: Photo `0x05` / Pocket 4 `0x17` / Live Photo `0x4D`. SuperNight `0x28` is video. */
    fun isPhotoMode(shootingMode: Int): Boolean =
        shootingMode == SHOOT_PHOTO ||
            shootingMode == SHOOT_PHOTO_POCKET4 ||
            shootingMode == SHOOT_LIVE_PHOTO

    /**
     * Label for a tabled `0x02/0xE1` value, or null when the camera reports one we do not know.
     * Both photo encodings read back as "Photo" — the body decides which it uses.
     * Pocket 3 presents `0x28` as Low-Light video; other bodies keep SuperNight.
     */
    /** [profile] carries a brand's names (Insta360 TimeShift / PureVideo) for this session. */
    fun shootingModeLabel(raw: Int, cameraName: String? = null, profile: CameraProfile = CameraProfile.DJI): String? =
        profile.shootingModeLabels[raw] ?: when (raw) {
            SHOOT_SLOWMO -> "SlowMo"
            SHOOT_VIDEO -> "Video"
            SHOOT_TIMELAPSE -> "TimeLapse"
            SHOOT_PHOTO, SHOOT_PHOTO_POCKET4 -> "Photo"
            SHOOT_LIVE_PHOTO -> "Live Photo"
            SHOOT_HYPERLAPSE -> "HyperLapse"
            SHOOT_SUPER_NIGHT ->
                if (CameraModel.looksLikePocket3(cameraName.orEmpty())) "Low-Light" else "SuperNight"
            else -> null
        }

    /**
     * Photo is the one mode whose `0x02/0xE1` value is body-dependent: Pocket 4 / 4 Pro take
     * `0x17`, and a Nano rejects that and takes `0x05`.
     */
    fun photoModeRaw(cameraName: String?): Int {
        val n = cameraName.orEmpty().lowercase().replace(" ", "")
        return if (n.contains("pocket4")) SHOOT_PHOTO_POCKET4 else SHOOT_PHOTO
    }

    /**
     * The camera's own on-screen carousel order — Video, Photo, TimeLapse, HyperLapse,
     * SuperNight (Low-Light on Pocket 3), SlowMo — which is not the numeric order. The
     * wire enum is sparse and unordered, so this is tabled and never computed.
     *
     * Only ever send a value from this table. Sweeping the `0x02/0xE1` value space froze a Nano
     * solid and needed a power cycle, so an unlisted mode must be refused rather than passed
     * through (Osmosis `MEDIA_PROTOCOL.md` §13a, DJI-Remote `engine_media.c`).
     *
     * Panorama (`0x0c`) is documented but left out: no hardware here has confirmed it.
     *
     * Note this is `0x02/0xE1`, never `0x02/0x02`. That opcode is nominally DJI's four-value
     * *work* mode, but on a Nano it **is** record control — a "Video" entry mapped to `[01]`
     * would start a recording behind the operator's back.
     */
    fun shootingModeCarousel(cameraName: String?): List<Int> =
        listOf(
            SHOOT_VIDEO,
            photoModeRaw(cameraName),
            SHOOT_TIMELAPSE,
            SHOOT_HYPERLAPSE,
            SHOOT_SUPER_NIGHT,
            SHOOT_SLOWMO,
        )

    fun zoomLens(position: Int): ByteArray {
        val p = position.coerceIn(0, 0xFFFF)
        return byteArrayOf(0x0A, 0x4E, (p and 0xFF).toByte(), ((p shr 8) and 0xFF).toByte())
    }

    fun zoomSlew(value: Int): ByteArray {
        val v = value.coerceIn(0, 0xFFFF)
        return byteArrayOf(0x03, 0x00, (v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte())
    }

    fun zoomStop(): ByteArray = byteArrayOf(0xFF.toByte(), 0x00, 0x00, 0x00)

    /** Chip stops land on slider lens (Pro 217 / 651 / 1302 / 2604; 2× / 4× interpolate). */
    fun lensForZoomFactor(factor: Double): Int =
        when (val write = CamFov.chipWrite(factor)) {
            is CamFov.ChipWrite.Lens -> write.position
            else -> CamFov.lensPosition(factor)
        }

    /** Native timed target: yaw/roll/pitch i16 LE, absolute + ignore roll, duration in 0.1s. */
    fun gimbalTimedTarget(target: GimbalWaypoint, duration: Double): ByteArray? {
        if (target.pitchDeg !in GimbalWaypoint.TILT_MIN_DEG..GimbalWaypoint.TILT_MAX_DEG) return null
        val nativePitch = target.nativePitchDeg ?: return null
        return gimbalTimedTarget(target.yawDeg, nativePitch, duration)
    }

    fun gimbalTimedTarget(yawDeg: Double, nativePitchDeg: Double, duration: Double): ByteArray? {
        if (!yawDeg.isFinite() || !nativePitchDeg.isFinite() || !duration.isFinite() ||
            yawDeg !in GimbalWaypoint.PAN_MIN_DEG..GimbalWaypoint.PAN_MAX_DEG ||
            nativePitchDeg !in -180.0..180.0 || duration !in 0.1..25.5 ||
            kotlin.math.abs(duration * 10 - kotlin.math.round(duration * 10)) >= 1e-6) return null
        fun tenth(value: Double): Int =
            java.lang.Math.copySign(kotlin.math.floor(kotlin.math.abs(value * 10) + 0.5), value).toInt()
        return u16LE(tenth(yawDeg)) + u16LE(0) + u16LE(tenth(nativePitchDeg)) +
            byteArrayOf(0x05, tenth(duration).toByte())
    }

    fun trackingBox(id: Int, x: Float, y: Float, width: Float, height: Float): ByteArray {
        val uid = id and 0xFFFF
        return byteArrayOf(0x01, 0x00, 0x00) +
            u16LE(uid) +
            floatLE(x) +
            floatLE(y) +
            floatLE(width) +
            floatLE(height)
    }

    fun pollTracking(): ByteArray = byteArrayOf(0x00)

    /** Action 6 moves On/Off to byte 1 and sends its captured tail verbatim (handbook `devices/action-6/coverage`). */
    fun setMediaFavorite(handle: Int, on: Boolean, counter: Int, cameraName: String = ""): ByteArray =
        if (CameraModel.looksLikeAction6(cameraName)) {
            byteArrayOf(0x01, if (on) 0x01 else 0x00) +
                u32LE(handle) +
                byteArrayOf(0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00)
        } else {
            byteArrayOf(0x01, 0x01) +
                u32LE(handle) +
                u32LE(counter) +
                byteArrayOf(0x00, if (on) 0x01 else 0x00, 0x00, 0x00, 0x00)
        }

    const val GIMBAL_STICK_CENTER = 1024
    const val GIMBAL_STICK_TRAVEL = 550
    const val GIMBAL_STICK_MIN = 474
    const val GIMBAL_STICK_MAX = 1574
    const val GIMBAL_STICK_DEADZONE = 0.08f
    const val GIMBAL_STICK_ANALOG_EXPO = 2.0
    const val GIMBAL_STICK_DEFAULT_DEADZONE_PERCENT = 8

    const val GIMBAL_STICK_DEFAULT_SENSITIVITY = 4

    enum class VirtualJoystickCurve(val raw: String, val expo: Double, val label: String) {
        LINEAR("linear", 1.0, "Linear"),
        STANDARD("standard", GIMBAL_STICK_ANALOG_EXPO, "Standard"),
        FINE("fine", 3.0, "Fine"),
        ;

        companion object {
            fun parse(raw: String?): VirtualJoystickCurve =
                entries.firstOrNull { it.raw.equals(raw, ignoreCase = true) } ?: STANDARD

            fun fromLabel(label: String): VirtualJoystickCurve =
                entries.firstOrNull { it.label == label } ?: STANDARD
        }
    }

    data class VirtualJoystickMapping(
        val invertPan: Boolean = false,
        val invertTilt: Boolean = false,
        val deadzone: Float = GIMBAL_STICK_DEADZONE,
        val curve: VirtualJoystickCurve = VirtualJoystickCurve.STANDARD,
    ) {
        val isDefault: Boolean
            get() = this == DEFAULT

        companion object {
            val DEFAULT = VirtualJoystickMapping()

            fun clampedDeadzone(value: Float): Float =
                if (value.isFinite()) value.coerceIn(0f, 0.25f) else GIMBAL_STICK_DEADZONE

            fun clampedDeadzonePercent(value: Int): Int = value.coerceIn(0, 25)

            fun deadzoneFromPercent(percent: Int): Float {
                val p = clampedDeadzonePercent(percent)
                return if (p == GIMBAL_STICK_DEFAULT_DEADZONE_PERCENT) GIMBAL_STICK_DEADZONE
                else p / 100f
            }

            fun resolvedDeadzonePercent(stored: Int?): Int =
                if (stored == null) GIMBAL_STICK_DEFAULT_DEADZONE_PERCENT
                else clampedDeadzonePercent(stored)
        }
    }
    const val GIMBAL_STICK_TAP_SLOP = 0.18f
    /** Full command throw as a multiple of the visible outer radius (`stickSize / 2`). */
    const val GIMBAL_STICK_TOUCH_COMMAND_RADIUS_FACTOR = 1.35f

    data class GimbalStickTouchMapping(
        val visualX: Float,
        val visualY: Float,
        val commandX: Float,
        val commandY: Float,
        val isTap: Boolean,
        val engaged: Boolean,
        val emit: Boolean,
    )

    fun mapGimbalStickTouch(
        dx: Float,
        dy: Float,
        stickSize: Float,
        knobSize: Float,
        engaged: Boolean,
    ): GimbalStickTouchMapping {
        val size = if (stickSize.isFinite()) maxOf(stickSize, 0f) else 0f
        val knob = if (knobSize.isFinite()) maxOf(knobSize, 0f) else 0f
        val rawX = if (dx.isFinite()) dx else 0f
        val rawY = if (dy.isFinite()) dy else 0f
        val travel = maxOf((size - knob) / 2f, 0f)
        val commandRadius = GIMBAL_STICK_TOUCH_COMMAND_RADIUS_FACTOR * (size / 2f)
        val (visualX, visualY) = radialClamp(rawX, rawY, travel)
        val visualMag = hypot(visualX, visualY)
        val visualNorm = if (travel > 0f) visualMag / travel else 0f
        val isTap = visualNorm <= GIMBAL_STICK_TAP_SLOP
        val nowEngaged = engaged || !isTap
        val (cmdX, cmdY) = radialClamp(rawX, rawY, commandRadius)
        val commandX = if (commandRadius > 0f) cmdX / commandRadius else 0f
        val commandY = if (commandRadius > 0f) -cmdY / commandRadius else 0f
        return GimbalStickTouchMapping(
            visualX = visualX,
            visualY = visualY,
            commandX = commandX,
            commandY = commandY,
            isTap = isTap,
            engaged = nowEngaged,
            emit = nowEngaged,
        )
    }

    private fun radialClamp(x: Float, y: Float, radius: Float): Pair<Float, Float> {
        val mag = hypot(x, y)
        if (radius <= 0f || mag <= radius) return x to y
        val scale = radius / mag
        return x * scale to y * scale
    }

    const val GIMBAL_FACE_UNKNOWN = -1
    const val GIMBAL_FACE_FRONT = 0
    const val GIMBAL_FACE_SELFIE = 1

    /** View-space X flip: TT180 extra-mirror XOR MIRROR assist. */
    fun liveViewFlip(poseViewFlip: Boolean, assistMirror: Boolean): Boolean =
        poseViewFlip != assistMirror

    /** Stick invert follows the visible picture (TT180 XOR MIRROR). */
    fun liveInvertPan(poseInvert: Boolean, assistMirror: Boolean): Boolean =
        poseInvert != assistMirror

    /** 4 = 1.0 (captured ±550 throw). 5 saturates earlier; 1–3 never reach full throw. */
    fun gimbalSensitivityGain(sensitivity: Int): Float =
        sensitivity.coerceIn(1, 5) / GIMBAL_STICK_DEFAULT_SENSITIVITY.toFloat()

    /** Deadzone, then linear remainder onto −1…1. Zoom stick uses this (no expo). */
    fun gimbalLinearThrow(
        normalized: Float,
        deadzone: Float = GIMBAL_STICK_DEADZONE,
    ): Float {
        val n = normalized.coerceIn(-1f, 1f)
        val magnitude = kotlin.math.abs(n)
        val rest = VirtualJoystickMapping.clampedDeadzone(deadzone)
        if (magnitude < rest) return 0f
        val span = 1f - rest
        if (span <= 0f) return 0f
        val t = (magnitude - rest) / span
        return if (n < 0f) -t else t
    }

    /** Deadzone, then expo ease-in onto −1…1. Full throw stays 1. Rest stays 0. */
    fun gimbalAnalogCurve(
        normalized: Float,
        deadzone: Float = GIMBAL_STICK_DEADZONE,
        expo: Double = GIMBAL_STICK_ANALOG_EXPO,
    ): Float {
        val t = gimbalLinearThrow(normalized, deadzone)
        if (t == 0f) return 0f
        val power = if (expo.isFinite() && expo > 0.0) expo else GIMBAL_STICK_ANALOG_EXPO
        val curved = kotlin.math.abs(t).toDouble().pow(power).toFloat()
        return if (t < 0f) -curved else curved
    }

    /** `x` −1…1 left…right → pan (axis1). `y` −1…1 down…up → tilt (axis0). */
    fun gimbalAxisLinear(normalized: Float): Int {
        val n = normalized.coerceIn(-1f, 1f)
        if (kotlin.math.abs(n) < 0.02f) return GIMBAL_STICK_CENTER
        return (GIMBAL_STICK_CENTER + n * GIMBAL_STICK_TRAVEL)
            .roundToInt()
            .coerceIn(GIMBAL_STICK_MIN, GIMBAL_STICK_MAX)
    }

    fun gimbalAxis(
        normalized: Float,
        sensitivity: Int = GIMBAL_STICK_DEFAULT_SENSITIVITY,
        mapping: VirtualJoystickMapping = VirtualJoystickMapping.DEFAULT,
    ): Int {
        val curved = gimbalAnalogCurve(normalized, mapping.deadzone, mapping.curve.expo)
        if (curved == 0f) return GIMBAL_STICK_CENTER
        val scaled = (curved * gimbalSensitivityGain(sensitivity)).coerceIn(-1f, 1f)
        return (GIMBAL_STICK_CENTER + scaled * GIMBAL_STICK_TRAVEL)
            .roundToInt()
            .coerceIn(GIMBAL_STICK_MIN, GIMBAL_STICK_MAX)
    }

    /** Invert pan in selfie so the throw stays screen-relative. Tilt is unchanged. */
    fun gimbalAxes(
        x: Float,
        y: Float,
        invertPan: Boolean = false,
        sensitivity: Int = GIMBAL_STICK_DEFAULT_SENSITIVITY,
        mapping: VirtualJoystickMapping = VirtualJoystickMapping.DEFAULT,
        linear: Boolean = false,
    ): Pair<Int, Int> {
        if (linear) {
            val pan = if (invertPan) -x else x
            return gimbalAxisLinear(y) to gimbalAxisLinear(pan)
        }
        val pan = if (invertPan != mapping.invertPan) -x else x
        val tilt = if (mapping.invertTilt) -y else y
        return gimbalAxis(tilt, sensitivity, mapping) to gimbalAxis(pan, sensitivity, mapping)
    }

    /**
     * iOS `CameraStatusDecoder.fps(index:)` — subscribe display table,
     * including SlowMo 100/120/240. FORMAT SET still only writes a pair
     * the body advertised (or Video 24–60 when camcap is empty).
     */
    fun fpsFromSubscribeIndex(index: Int): Int? = VideoFrameRate.fps(index)

    fun resolutionLabel(code: Int): String = VideoResolution.fromRaw(code)?.label ?: "—"

    /** [profile] carries a brand's names (Insta360 calls Normal "Standard") for this session. */
    fun colorLabel(mode: Int, family: String = "pocket", profile: CameraProfile = CameraProfile.DJI): String =
        profile.colorLabels[mode] ?: when (mode) {
            COLOR_NORMAL -> if (family == "nano") "Normal 8-bit" else "Normal"
            COLOR_HDR -> "HDR"
            COLOR_DLOG -> "D-Log"
            COLOR_DLOG2 -> "D-Log2"
            COLOR_NORMAL10 -> "Normal 10-bit"
            COLOR_DLOG_M -> if (family == "nano") "D-Log M 10-bit" else "D-Log M"
            COLOR_ILOG -> "I-Log"
            COLOR_DOLBY_VISION -> "Dolby Vision"
            else -> "—"
        }

    /** `IsoIndex.allCases` raw bytes. Unknown camcap entries are dropped. */
    val ISO_INDEX_ALL = listOf(0x00, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B)
    /** Insta360 Luna ISO stop. Not a DJI index byte, so not in the DJI ladder above. */
    const val ISO_160 = 0xE0
    val ISO_INDEX_BYTES = (ISO_INDEX_ALL + ISO_160).toSet()

    fun isoLabel(index: Int): String =
        when (index) {
            0x00 -> "Auto"
            0x03 -> "100"
            0x04 -> "200"
            0x05 -> "400"
            0x06 -> "800"
            0x07 -> "1600"
            0x08 -> "3200"
            0x09 -> "6400"
            0x0A -> "12800"
            0x0B -> "25600"
            ISO_160 -> "160"
            else -> "—"
        }

    /** nil for Auto / unknown — matches Swift `IsoIndex.isoValue`. */
    fun isoValue(index: Int): Int? =
        when (index) {
            0x03 -> 100
            0x04 -> 200
            0x05 -> 400
            0x06 -> 800
            0x07 -> 1600
            0x08 -> 3200
            0x09 -> 6400
            0x0A -> 12800
            0x0B -> 25600
            ISO_160 -> 160
            else -> null
        }

    fun isoIndexFromValue(iso: Int): Int? =
        when (iso) {
            100 -> 0x03
            200 -> 0x04
            400 -> 0x05
            800 -> 0x06
            1600 -> 0x07
            3200 -> 0x08
            6400 -> 0x09
            12800 -> 0x0A
            25600 -> 0x0B
            160 -> ISO_160
            else -> null
        }

    /** D-Log2 has no Auto ISO. Unknown color is treated as Normal. */
    fun offersIsoAuto(colorMode: Int): Boolean = colorMode != COLOR_DLOG2

    /** GET `0x8E` pid `0x000F` only when Auto ISO exists. */
    fun shouldGetIsoLimit(colorMode: Int): Boolean = offersIsoAuto(colorMode)

    fun isoWheelIndices(available: List<Int>, fallback: List<Int>): List<Int> =
        if (available.isEmpty()) fallback else available

    /**
     * Native base ISO for D-Log ↔ D-Log2 hops. Rec.709 / HLG / D-Log M / unknown:
     * none. Hop uses this, not [markedIsoLabel] (D-Log M stars 400 but does not hop).
     */
    fun baseIsoLabel(colorMode: Int): String? =
        when (colorMode) {
            COLOR_DLOG -> "400"
            COLOR_DLOG2 -> "1600"
            else -> null
        }

    /**
     * If the operator is still on [from]'s native ISO, hop to [to]'s native.
     * Off-base or Auto stays put. Rec.709 / HDR / D-Log M have no native — no hop.
     */
    fun nativeIsoHop(from: Int, to: Int, currentIndex: Int, hopEnabled: Boolean): Int? {
        if (!hopEnabled || from == to) return null
        val fromBase = baseIsoLabel(from)?.toIntOrNull() ?: return null
        val toBase = baseIsoLabel(to)?.toIntOrNull() ?: return null
        val current = isoValue(currentIndex) ?: return null
        if (current != fromBase) return null
        return isoIndexFromValue(toBase)
    }

    /**
     * Star on the ISO wheel. Follows `cam_image_effect` `@2` after the body
     * reports, mapped like iOS `MonitorTransfer` — D-Log / D-Log M = 400,
     * D-Log2 = 1600. Rec.709 / HLG / unknown: none. Not a tele hop SET.
     */
    fun markedIsoLabel(colorMode: Int): String? =
        when (colorMode) {
            COLOR_DLOG, COLOR_DLOG_M -> "400"
            COLOR_DLOG2 -> "1600"
            else -> null
        }

    fun isoChoices(colorMode: Int): List<Pair<Int, String>> {
        val all =
            listOf(
                0x00 to "Auto",
                0x03 to "100",
                0x04 to "200",
                0x05 to "400",
                0x06 to "800",
                0x07 to "1600",
                0x08 to "3200",
                0x09 to "6400",
                0x0A to "12800",
                0x0B to "25600",
            )
        val allowed =
            when (colorMode) {
                COLOR_DLOG2 -> setOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
                COLOR_DLOG -> setOf(0x00, 0x05, 0x06, 0x07, 0x08, 0x09)
                else -> setOf(0x00, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B)
            }
        return all.filter { it.first in allowed }
    }

    fun parseShutterDenoms(value: ByteArray): List<Int> {
        if (value.size < 13 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 10 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[9].toInt() and 0xFF
        val payload = body.copyOfRange(10, body.size)
        if (count <= 0 || payload.size != count * 3) return emptyList()
        val out = ArrayList<Int>(count)
        val seen = HashSet<Int>()
        var i = 0
        while (i + 2 < payload.size) {
            val raw = (payload[i].toInt() and 0xFF) or ((payload[i + 1].toInt() and 0xFF) shl 8)
            if (raw and 0x8000 != 0) {
                val denom = raw and 0x7FFF
                if (denom in 1..16_000 && seen.add(denom)) out.add(denom)
            }
            i += 3
        }
        return out
    }

    /**
     * `camcap_video_format` — legal `[res][fps]` pairs for the current shooting
     * mode. Pocket 4 Pro Video (`mimo-live-start-20260828`): `01 25 00 0c` then
     * 12× `[res][fps_idx] 00` — 4K 24–60 then 1080p 60–24.
     */
    fun parseVideoFormats(value: ByteArray): List<VideoFormat> {
        if (value.size < 5 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 2 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[0].toInt() and 0xFF
        if (count < 1 || body.size < 1 + count * 3) return emptyList()
        val out = ArrayList<VideoFormat>(count)
        var i = 1
        repeat(count) {
            if (i + 1 >= body.size) return@repeat
            val res = body[i].toInt() and 0xFF
            val fps = body[i + 1].toInt() and 0xFF
            VideoFormat.parse(res, fps)?.let { if (it !in out) out.add(it) }
            i += 3
        }
        return out
    }

    fun parseIsoIndices(value: ByteArray): List<Int> {
        if (value.size < 5 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 2 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[1].toInt() and 0xFF
        if (body[0].toInt() != 0 || count < 1 || body.size < 2 + count) return emptyList()
        return body.copyOfRange(2, 2 + count).map { it.toInt() and 0xFF }.filter { it in ISO_INDEX_BYTES }
    }

    /** Pocket 3 empty-camcap video ladder. Fast-first, matching iOS `CamCapShutter`. */
    val emptyCapVideoDenoms: List<Int> = listOf(
        8000, 6400, 4000, 3200, 2000, 1600, 1000, 800, 500, 400, 250, 200,
        125, 120, 100, 60, 50, 48, 40, 30, 25, 24,
    )

    fun shutterWheelDenoms(available: List<Int>, current: Int): List<Int> {
        if (available.isNotEmpty()) return available
        return mergeCurrentShutter(current, emptyCapVideoDenoms)
    }

    private fun mergeCurrentShutter(current: Int, ladder: List<Int>): List<Int> {
        if (current !in 1..16_000 || current in ladder) return ladder
        val out = ladder.toMutableList()
        val idx = out.indexOfFirst { it < current }
        if (idx >= 0) out.add(idx, current) else out.add(current)
        return out
    }

    /** Next / previous 1/N in camera order (fast-first). nil at the end. */
    fun shutterSteppedDenom(from: Int, steps: Int, available: List<Int>): Int? {
        val list = shutterWheelDenoms(available, from)
        val nearest = list.minByOrNull { kotlin.math.abs(it - from) } ?: return null
        val idx = list.indexOf(from).takeIf { it >= 0 } ?: list.indexOf(nearest)
        val next = idx + steps
        if (next !in list.indices || next == idx) return null
        return list[next]
    }

    /** Next / previous full-stop ISO. Skips Auto. nil at the end. */
    fun isoStepped(from: Int, steps: Int, available: List<Int>): Int? {
        val list = available.filter { it != 0x00 }
        val idx = list.indexOf(from)
        if (from == 0x00 || idx < 0) return null
        val next = idx + steps
        if (next !in list.indices || next == idx) return null
        return list[next]
    }

    private fun u16LE(value: Int): ByteArray =
        byteArrayOf((value and 0xFF).toByte(), ((value shr 8) and 0xFF).toByte())

    private fun u32LE(value: Int): ByteArray =
        byteArrayOf(
            (value and 0xFF).toByte(),
            ((value shr 8) and 0xFF).toByte(),
            ((value shr 16) and 0xFF).toByte(),
            ((value shr 24) and 0xFF).toByte(),
        )

    private fun floatLE(value: Float): ByteArray {
        val bits = value.toRawBits()
        return byteArrayOf(
            (bits and 0xFF).toByte(),
            ((bits shr 8) and 0xFF).toByte(),
            ((bits shr 16) and 0xFF).toByte(),
            ((bits shr 24) and 0xFF).toByte(),
        )
    }
}

/** AF-C submenu. `0x02/0x8E` pid `0x003B`. SET/GET value is `01 <mode>`. */
enum class FocusTrackMode(val raw: Int, val label: String) {
    DEFAULT(0x00, "Default"),
    PRODUCT_SHOWCASE(0x01, "Product Showcase"),
    SUBJECT_LOCK(0x02, "Subject Lock Tracking"),
    REGISTERED_PRIORITY(0x03, "Registered Subject Priority"),
    ;

    companion object {
        /** Camera can pause HEVC while switching AF-C intelligence. */
        const val VIDEO_GRACE_SEC = 4.0

        fun fromRaw(raw: Int): FocusTrackMode? = entries.firstOrNull { it.raw == raw }

        fun shouldHoldWatchdog(secondsSinceSet: Double?): Boolean {
            val s = secondsSinceSet ?: return false
            return s >= 0.0 && s < VIDEO_GRACE_SEC
        }
    }
}

/** FOCUS picker + capture-strip chip. Single is `0x24`. The rest are AF-C + pid `0x003B`. */
enum class FocusOption(val chip: String) {
    SINGLE("AF-S"),
    CONTINUOUS_DEFAULT("AF-C"),
    PRODUCT_SHOWCASE("Showcase"),
    SUBJECT_LOCK("Lock"),
    REGISTERED_PRIORITY("Priority"),
    ;

    companion object {
        fun resolve(mode: Int, track: Int): FocusOption? =
            when (mode) {
                CameraCommands.FOCUS_SINGLE -> SINGLE
                CameraCommands.FOCUS_CONTINUOUS ->
                    when (FocusTrackMode.fromRaw(track)) {
                        FocusTrackMode.PRODUCT_SHOWCASE -> PRODUCT_SHOWCASE
                        FocusTrackMode.SUBJECT_LOCK -> SUBJECT_LOCK
                        FocusTrackMode.REGISTERED_PRIORITY -> REGISTERED_PRIORITY
                        FocusTrackMode.DEFAULT, null -> CONTINUOUS_DEFAULT
                    }
                else -> null
            }
    }
}


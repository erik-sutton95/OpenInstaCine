package com.opencapture.openinstacine.luna

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Luna control requests, byte-for-byte ports of Adapters/Insta360Protocol `LunaControl.swift`
 * and `LunaProtocol.swift`. All are plaintext on TCP 6666. [functionMode] is the settings bank
 * the shooting mode reads (7 normal video); the backend passes the active one.
 */
internal object LunaControl {
    const val SET_OPTIONS = 7
    const val GET_OPTIONS = 8
    const val SET_PHOTOGRAPHY_OPTIONS = 9
    const val GET_PHOTOGRAPHY_OPTIONS = 10
    const val GIMBAL_CONTROL = 226
    const val OPEN_TRACKING = 237
    const val CANCEL_TRACKING = 238
    const val MAXIMUM_ZOOM = 15.0
    const val FUNCTION_MODE_VIDEO = 7
    /** Observed official shutter-SET ISO top limit: UInt32 wrap of -3200, not an ISO. */
    const val OFFICIAL_ISO_TOP_LIMIT = 4_294_964_096L

    class Request(val code: Int, val body: ByteArray)

    private fun tag(field: Int, wire: Int) = LunaWire.varint(((field shl 3) or wire).toLong())
    private fun sint32(field: Int, value: Int) = LunaWire.integer(field, ((value shl 1) xor (value shr 31)).toLong() and 0xFFFF_FFFFL)
    private fun double(field: Int, value: Double) =
        tag(field, 1) + ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putDouble(value).array()
    private fun float(field: Int, value: Float) =
        tag(field, 5) + ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(value).array()
    private fun packed(values: List<Int>) = values.fold(ByteArray(0)) { acc, v -> acc + LunaWire.varint(v.toLong()) }
    private fun joined(fields: Map<Int, ByteArray>) = fields.toSortedMap().values.fold(ByteArray(0)) { acc, b -> acc + b }

    // Official cmd 9 shape.

    /** Whole PhotographyOptions with defaults 20, 21, 31, 88 present; the camera applies only [types]. */
    fun photographySet(types: List<Int>, fields: Map<Int, ByteArray>, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        val all = mapOf(
            20 to LunaWire.blob(20, ByteArray(0)),
            21 to LunaWire.blob(21, ByteArray(0)),
            31 to LunaWire.integer(31, 1),
            88 to LunaWire.integer(88, 1),
        ) + fields
        val body = LunaWire.blob(1, packed(types)) + LunaWire.blob(2, joined(all)) + LunaWire.integer(3, functionMode.toLong())
        return Request(SET_PHOTOGRAPHY_OPTIONS, body)
    }

    /** Scalar option; zero is encoded explicitly (fw 1.1.15 ignores an omitted FOV 33). */
    fun photographyValue(type: Int, value: Long, functionMode: Int = FUNCTION_MODE_VIDEO) =
        photographySet(listOf(type), mapOf(type to LunaWire.integer(type, value)), functionMode)

    /** Schema `sint32` tenths: +0.3 EV -> 3 -> wire 6. */
    fun exposureBias(stops: Double, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        require(stops.isFinite() && abs(stops) <= 4)
        val tenths = (stops * 10).roundToInt()
        return photographySet(listOf(7), if (tenths == 0) emptyMap() else mapOf(7 to sint32(7, tenths)), functionMode)
    }

    /** Observed: 1 Standard, 2 I-Log, 5 Dolby Vision. */
    fun colorMode(mode: Long, functionMode: Int = FUNCTION_MODE_VIDEO) = photographyValue(35, mode, functionMode)

    fun whiteBalanceKelvin(kelvin: Long, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        require(kelvin in 2000..10000)
        return photographyValue(39, kelvin, functionMode)
    }

    /** Official WB Auto is type 39 with the value omitted. */
    fun whiteBalanceAuto(functionMode: Int = FUNCTION_MODE_VIDEO) = photographySet(listOf(39), emptyMap(), functionMode)

    /** fw 1.1.15 stores 1...15; values outside are ignored, not clamped. */
    fun zoom(factor: Double, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        require(factor in 1.0..MAXIMUM_ZOOM)
        return photographySet(listOf(53), mapOf(53 to double(53, factor)), functionMode)
    }

    /** Observed types [31, 63] (resolution + HDR switch). */
    fun recordResolution(raw: Long, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        require(raw > 0)
        return photographySet(listOf(31, 63), mapOf(31 to LunaWire.integer(31, raw)), functionMode)
    }

    /** The shell's independent ISO / shutter drums map onto Luna's four programs. */
    fun exposureProgram(iso: Long?, shutterSeconds: Double?): Int = when {
        iso == null && shutterSeconds == null -> 0
        shutterSeconds == null -> 1
        iso == null -> 2
        else -> 3
    }

    /**
     * Official exposure SETs (field 21, IQ_3A_MODE 100 = 2 PRO). Auto ISO in a shutter program adds
     * the ISO top-limit sentinel (types 21, 24, 100). Manual with an explicit ISO omits it: on fw
     * 1.1.15 the sentinel turns program 3 into 2 and drops the ISO.
     */
    fun videoExposure(program: Int, iso: Long? = null, shutterSeconds: Double? = null, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        if (shutterSeconds != null) require(shutterSeconds > 0 && shutterSeconds <= 60)
        var exposure = if (program == 0) ByteArray(0) else LunaWire.integer(1, program.toLong())
        if (iso != null && iso > 0) exposure += LunaWire.integer(2, iso)
        if (shutterSeconds != null) exposure += double(3, shutterSeconds)
        val fields = mutableMapOf(21 to LunaWire.blob(21, exposure), 100 to LunaWire.integer(100, 2))
        val autoIso = program == 2 || (program == 3 && (iso ?: 0L) == 0L)
        if (autoIso) fields[24] = LunaWire.integer(24, OFFICIAL_ISO_TOP_LIMIT)
        return photographySet(if (autoIso) listOf(21, 24, 100) else listOf(21, 100), fields, functionMode)
    }

    /** Option 91 field 2: 1 slow, 2 medium, 3 fast, 4 sensitive. */
    fun gimbalFollowSpeed(speed: Long, functionMode: Int = FUNCTION_MODE_VIDEO) =
        photographySet(listOf(91), mapOf(91 to LunaWire.blob(91, LunaWire.integer(2, speed))), functionMode)

    /** Option 91 field 4: 1 FPV, 2 Roll Lock, 3 Roll & Tilt Lock, 4 FPV-V. */
    fun gimbalMode(mode: Long, functionMode: Int = FUNCTION_MODE_VIDEO) =
        photographySet(listOf(91), mapOf(91 to LunaWire.blob(91, LunaWire.integer(4, mode))), functionMode)

    private fun roi(values: List<Double>, firstField: Int): ByteArray {
        require(values.all { it in 0.0..1.0 })
        return values.withIndex().filter { it.value != 0.0 }
            .fold(ByteArray(0)) { acc, (offset, value) -> acc + float(firstField + offset, value.toFloat()) }
    }

    fun tapFocus(x: Double, y: Double, width: Double = 0.15, height: Double = 0.27, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        val params = LunaWire.integer(1, 1) + roi(listOf(x, y, width, height), 2)
        return photographySet(listOf(94), mapOf(94 to LunaWire.blob(94, params)), functionMode)
    }

    fun openTracking(x: Double, y: Double, width: Double, height: Double, nowMillis: Long = System.currentTimeMillis()): Request =
        Request(OPEN_TRACKING, LunaWire.integer(1, nowMillis) + roi(listOf(x, y, width, height), 2))

    val cancelTracking = Request(CANCEL_TRACKING, ByteArray(0))

    /** Action 1 move, 2 recenter, 3 flip. Axes -99..99; a move with both axes zero releases the stick. */
    fun gimbal(action: Int, upDown: Int = 0, leftRight: Int = 0): Request {
        require(upDown in -99..99 && leftRight in -99..99)
        var remote = ByteArray(0)
        if (upDown != 0) remote += sint32(1, upDown)
        if (leftRight != 0) remote += sint32(2, leftRight)
        return Request(GIMBAL_CONTROL, LunaWire.integer(1, action.toLong()) + LunaWire.blob(2, remote))
    }

    fun gimbalStick(pan: Double, tilt: Double): Request = gimbal(
        1,
        upDown = Math.round(tilt.coerceIn(-1.0, 1.0) * 99).toInt(),
        leftRight = Math.round(pan.coerceIn(-1.0, 1.0) * 99).toInt(),
    )

    // Official cmd 7 shape: cached device Options (1 = 1, 5 = 48000, 42 = 1, 82 = 3) around one field.

    fun deviceSet(type: Int, value: Long): Request {
        val all = mapOf(
            1 to LunaWire.integer(1, 1),
            5 to LunaWire.integer(5, 48_000),
            42 to LunaWire.integer(42, 1),
            82 to LunaWire.integer(82, 3),
        ) + (if (value == 0L) emptyMap() else mapOf(type to LunaWire.integer(type, value)))
        return Request(SET_OPTIONS, LunaWire.blob(1, packed(listOf(type))) + LunaWire.blob(2, joined(all)))
    }

    // Capture, media and status requests.

    val startLive = Request(1, LunaWire.liveBody)
    val stopLive = Request(2, ByteArray(0))
    /** Mode 0 (normal) is omitted; 5 is 360 gimbal pano. */
    fun takePicture(mode: Long = 0) = Request(3, if (mode == 0L) ByteArray(0) else LunaWire.integer(1, mode))
    /** Field 1 = 1 `Capture_MODE_NORMAL`. */
    val startCapture = Request(4, byteArrayOf(8, 1))
    val stopCapture = Request(5, ByteArray(0))
    val captureStatus = Request(15, ByteArray(0))

    /** Official shape: media type 2 (video and photo), limit INT32_MAX, card location. */
    fun fileList(mediaType: Long = 2, location: Long = 2): Request =
        Request(13, LunaWire.integer(1, mediaType) + LunaWire.integer(3, Int.MAX_VALUE.toLong()) + LunaWire.integer(4, location))

    fun fileInfoList(location: Long? = null) = Request(38, location?.let { LunaWire.integer(1, it) } ?: ByteArray(0))

    /** Extra type 1 metadata, 2 NV12 thumbnail. */
    fun fileExtra(path: String, extraType: Long? = null): Request {
        require(path.isNotEmpty())
        return Request(11, LunaWire.blob(1, path.toByteArray()) + (extraType?.let { LunaWire.integer(2, it) } ?: ByteArray(0)))
    }

    fun deleteFiles(uri: String): Request {
        require(uri.isNotEmpty() && uri.toByteArray().size <= 512)
        return Request(12, LunaWire.blob(1, uri.toByteArray()))
    }

    fun accessCameraFileState(state: Long) = Request(118, LunaWire.integer(1, state))

    private fun optionTypes(numbers: List<Int>, packed: Boolean): ByteArray {
        require(numbers.isNotEmpty() && numbers.size <= 256 && numbers.all { it > 0 && it < (1 shl 29) })
        return if (packed) LunaWire.blob(1, packed(numbers)) else numbers.fold(ByteArray(0)) { acc, n -> acc + LunaWire.integer(1, n.toLong()) }
    }

    fun getOptions(numbers: List<Int>, packed: Boolean = true) = Request(GET_OPTIONS, optionTypes(numbers, packed))

    /** Official 1 Hz poll: battery 11, storage 20, 85, screen battery 180. */
    val statusRequest = getOptions(listOf(11, 20, 85, 180))
    /** Official mode probe (41, 40, 65, 124, 132, 82, 135, 169, 173). */
    val shootingModeRequest = getOptions(listOf(41, 40, 65, 124, 132, 82, 135, 169, 173))

    fun getPhotographyOptions(types: List<Int>, functionMode: Int = FUNCTION_MODE_VIDEO, packed: Boolean = false) =
        Request(GET_PHOTOGRAPHY_OPTIONS, optionTypes(types, packed) + LunaWire.integer(2, functionMode.toLong()))

    /** Every photography type the monitor shows. */
    val settingTypes = listOf(6, 7, 18, 20, 21, 24, 31, 33, 35, 39, 40, 43, 53, 72, 73, 91, 92, 93, 100, 104)
}

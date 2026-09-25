package com.opencapture.openinstacine.luna

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Luna control requests, byte-for-byte ports of Adapters/Insta360Protocol `LunaControl.swift`
 * and `LunaProtocol.swift` (gimbal, zoom, tap focus, Deep Track). All are plaintext on TCP 6666.
 */
internal object LunaControl {
    const val SET_PHOTOGRAPHY_OPTIONS = 9
    const val GIMBAL_CONTROL = 226
    const val OPEN_TRACKING = 237
    const val CANCEL_TRACKING = 238
    const val MAXIMUM_ZOOM = 15.0
    /** Normal video. iOS reads the live mode from photography options; Android does not yet. */
    const val FUNCTION_MODE_VIDEO = 7

    class Request(val code: Int, val body: ByteArray)

    private fun tag(field: Int, wire: Int) = LunaWire.varint(((field shl 3) or wire).toLong())
    private fun sint32(field: Int, value: Int) = LunaWire.integer(field, ((value shl 1) xor (value shr 31)).toLong() and 0xFFFF_FFFFL)
    private fun double(field: Int, value: Double) =
        tag(field, 1) + ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putDouble(value).array()
    private fun float(field: Int, value: Float) =
        tag(field, 5) + ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putFloat(value).array()

    /** Official cmd 9 shape: whole PhotographyOptions with defaults 20, 21, 31, 88; camera applies only [types]. */
    fun photographySet(types: List<Int>, fields: Map<Int, ByteArray>, functionMode: Int = FUNCTION_MODE_VIDEO): Request {
        val all = sortedMapOf(
            20 to LunaWire.blob(20, ByteArray(0)),
            21 to LunaWire.blob(21, ByteArray(0)),
            31 to LunaWire.integer(31, 1),
            88 to LunaWire.integer(88, 1),
        ).apply { putAll(fields) }
        val nested = all.values.fold(ByteArray(0)) { acc, bytes -> acc + bytes }
        val packed = types.fold(ByteArray(0)) { acc, type -> acc + LunaWire.varint(type.toLong()) }
        val body = LunaWire.blob(1, packed) + LunaWire.blob(2, nested) + LunaWire.integer(3, functionMode.toLong())
        return Request(SET_PHOTOGRAPHY_OPTIONS, body)
    }

    fun zoom(factor: Double): Request {
        require(factor in 1.0..MAXIMUM_ZOOM)
        return photographySet(listOf(53), mapOf(53 to double(53, factor)))
    }

    private fun roi(values: List<Double>, firstField: Int): ByteArray {
        require(values.all { it in 0.0..1.0 })
        return values.withIndex().filter { it.value != 0.0 }
            .fold(ByteArray(0)) { acc, (offset, value) -> acc + float(firstField + offset, value.toFloat()) }
    }

    fun tapFocus(x: Double, y: Double, width: Double = 0.15, height: Double = 0.27): Request {
        val params = LunaWire.integer(1, 1) + roi(listOf(x, y, width, height), 2)
        return photographySet(listOf(94), mapOf(94 to LunaWire.blob(94, params)))
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
}

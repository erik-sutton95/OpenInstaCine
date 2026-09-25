package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.EvComp
import com.opencapture.openpocketcine.core.CameraColorProfile
import com.opencapture.openpocketcine.core.CameraGimbalMode
import com.opencapture.openpocketcine.core.CameraGimbalSpeed
import com.opencapture.openpocketcine.core.CameraReadout
import com.opencapture.openpocketcine.core.CameraRecordFormat
import com.opencapture.openpocketcine.core.CameraShootingMode
import java.util.Locale
import kotlin.math.roundToInt
import kotlin.reflect.KMutableProperty0

/** Optimistic values the operator asked for, held until the camera reports them (iOS `LunaControlPins`). */
internal class LunaControlPins {
    var isoIndex: CameraValuePin<Int>? = null
    var shutterDenom: CameraValuePin<Int>? = null
    var expoMode: CameraValuePin<Int>? = null
    var ev: CameraValuePin<Int>? = null
    /** (wbMode, kelvin); kelvin 0 for auto. */
    var whiteBalance: CameraValuePin<Pair<Int, Int>>? = null
    var color: CameraValuePin<Int>? = null
    var format: CameraValuePin<VideoFormat>? = null
    var shootingMode: CameraValuePin<Int>? = null
    var recording: CameraValuePin<Boolean>? = null
    var gimbalMode: CameraValuePin<GimbalMode>? = null
    var gimbalSpeed: CameraValuePin<GimbalSpeed>? = null
    var photoInFlight = false

    fun clear() {
        isoIndex = null; shutterDenom = null; expoMode = null; ev = null; whiteBalance = null; color = null
        format = null; shootingMode = null; recording = null; gimbalMode = null; gimbalSpeed = null; photoInFlight = false
    }
}

/** Held value while the pin is live; releases the pin on confirmation or expiry. */
internal fun <T> KMutableProperty0<CameraValuePin<T>?>.hold(reported: T?, now: Long): T? {
    val (held, pin) = CameraValuePin.reconcile(get(), reported, now)
    set(pin)
    return held
}

internal fun <T> pin(value: T, now: Long, settleMs: Long = CameraValuePin.SETTLE_MS) = CameraValuePin(value, now + settleMs)

/**
 * Luna (neutral core-api readout) to shared monitor vocabulary. Port of iOS `LunaShellMapping`:
 * wire numbers stay in the adapter; everything the shared screens read goes through here.
 */
internal object LunaShellMapping {
    /** ISO stops the official wheel offers. */
    val isoValues = listOf(100, 160, 200, 400, 800, 1600, 3200, 6400)
    val isoIndices = listOf(0) + isoValues.mapNotNull(CameraCommands::isoIndexFromValue)

    /** Official video wheel, slowest last. fw 1.1.15 adds 1/15 ... 1/5. */
    val shutterDenoms = listOf(
        8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 250,
        200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 15, 10, 5,
    )

    val colorModes = listOf(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_ILOG, CameraCommands.COLOR_DOLBY_VISION)

    /** Luna names for the shared mode drum (installed once at launch). */
    val shootingModeLabels = mapOf(
        CameraCommands.SHOOT_SLOWMO to "Slow Motion", CameraCommands.SHOOT_TIMELAPSE to "Timelapse",
        CameraCommands.SHOOT_HYPERLAPSE to "TimeShift", CameraCommands.SHOOT_SUPER_NIGHT to "PureVideo",
    )

    /** A Luna frame size the shared table has no byte for (photo sizes, 4:3). */
    val unknownResolution = VideoResolution(0xDF)

    fun shootingMode(mode: CameraShootingMode): Int = when (mode) {
        CameraShootingMode.VIDEO -> CameraCommands.SHOOT_VIDEO
        CameraShootingMode.TIMELAPSE -> CameraCommands.SHOOT_TIMELAPSE
        CameraShootingMode.TIMESHIFT -> CameraCommands.SHOOT_HYPERLAPSE
        CameraShootingMode.SLOW_MOTION -> CameraCommands.SHOOT_SLOWMO
        CameraShootingMode.PURE_VIDEO -> CameraCommands.SHOOT_SUPER_NIGHT
        CameraShootingMode.PHOTO, CameraShootingMode.PANO -> CameraCommands.SHOOT_PHOTO
    }

    fun cameraShootingMode(raw: Int): CameraShootingMode? = when (raw) {
        CameraCommands.SHOOT_VIDEO -> CameraShootingMode.VIDEO
        CameraCommands.SHOOT_TIMELAPSE -> CameraShootingMode.TIMELAPSE
        CameraCommands.SHOOT_HYPERLAPSE -> CameraShootingMode.TIMESHIFT
        CameraCommands.SHOOT_SLOWMO -> CameraShootingMode.SLOW_MOTION
        CameraCommands.SHOOT_SUPER_NIGHT -> CameraShootingMode.PURE_VIDEO
        CameraCommands.SHOOT_PHOTO, CameraCommands.SHOOT_PHOTO_POCKET4 -> CameraShootingMode.PHOTO
        else -> null
    }

    fun colorMode(profile: CameraColorProfile): Int = when (profile) {
        CameraColorProfile.LOG -> CameraCommands.COLOR_ILOG
        CameraColorProfile.DOLBY_VISION -> CameraCommands.COLOR_DOLBY_VISION
        CameraColorProfile.HDR -> CameraCommands.COLOR_HDR
        CameraColorProfile.STANDARD, CameraColorProfile.VIVID -> CameraCommands.COLOR_NORMAL
    }

    fun colorProfile(mode: Int): CameraColorProfile = when (mode) {
        CameraCommands.COLOR_ILOG, CameraCommands.COLOR_DLOG, CameraCommands.COLOR_DLOG2, CameraCommands.COLOR_DLOG_M -> CameraColorProfile.LOG
        CameraCommands.COLOR_DOLBY_VISION -> CameraColorProfile.DOLBY_VISION
        CameraCommands.COLOR_HDR -> CameraColorProfile.HDR
        else -> CameraColorProfile.STANDARD
    }

    fun gimbalMode(mode: CameraGimbalMode): GimbalMode? = when (mode) {
        CameraGimbalMode.ROLL_LOCK -> GimbalMode.FOLLOW
        CameraGimbalMode.ROLL_TILT_LOCK -> GimbalMode.TILT_LOCKED
        CameraGimbalMode.FPV, CameraGimbalMode.FPV_VERTICAL -> GimbalMode.FPV
        CameraGimbalMode.LOCK -> GimbalMode.DIRECTION_LOCK
        CameraGimbalMode.STABILIZED_VERTICAL -> null
    }

    fun cameraGimbalMode(mode: GimbalMode): CameraGimbalMode = when (mode) {
        GimbalMode.FOLLOW -> CameraGimbalMode.ROLL_LOCK
        GimbalMode.TILT_LOCKED -> CameraGimbalMode.ROLL_TILT_LOCK
        GimbalMode.FPV -> CameraGimbalMode.FPV
        GimbalMode.DIRECTION_LOCK -> CameraGimbalMode.LOCK
    }

    fun gimbalSpeed(speed: CameraGimbalSpeed): GimbalSpeed = when (speed) {
        CameraGimbalSpeed.SLOW -> GimbalSpeed.SLOW
        CameraGimbalSpeed.MEDIUM -> GimbalSpeed.DEFAULT
        CameraGimbalSpeed.FAST, CameraGimbalSpeed.SENSITIVE -> GimbalSpeed.FAST
    }

    fun cameraGimbalSpeed(speed: GimbalSpeed): CameraGimbalSpeed = when (speed) {
        GimbalSpeed.SLOW -> CameraGimbalSpeed.SLOW
        GimbalSpeed.DEFAULT -> CameraGimbalSpeed.MEDIUM
        GimbalSpeed.FAST -> CameraGimbalSpeed.FAST
    }

    /** Shared resolution byte for a Luna frame size: DJI bytes where the shape matches, Luna bytes (0xD0...) otherwise. */
    fun resolution(width: Int, height: Int): VideoResolution {
        val long = maxOf(width, height)
        val portrait = height > width
        return when {
            long == 1920 && !portrait -> VideoResolution.P1080
            long == 1920 -> VideoResolution.P1080_9X16
            long in 2688..2720 && !portrait -> VideoResolution.P2_7K
            long in 2688..2720 -> VideoResolution.P2_7K_9X16
            long in 2880..3072 && portrait -> VideoResolution.P3K_9X16
            long == 3840 && !portrait && height < 2000 -> VideoResolution.LUNA_4K_235
            long == 7680 && !portrait && height < 4000 -> VideoResolution.LUNA_8K_235
            long in 2880..3072 -> VideoResolution.LUNA_3K
            long == 3840 && !portrait -> VideoResolution.P4K
            long == 3840 -> VideoResolution.LUNA_4K_9X16
            long in 5120..5760 && !portrait -> VideoResolution.LUNA_6K
            long == 7680 && !portrait -> VideoResolution.LUNA_8K
            else -> unknownResolution
        }
    }

    fun videoFormat(format: CameraRecordFormat): VideoFormat? {
        val rate = VideoFrameRate.fromFps(format.fps.roundToInt()) ?: return null
        return VideoFormat(resolution(format.width, format.height), rate)
    }

    /** First backend value wins for each shared format (several Luna sizes share one chip). */
    fun formatTable(formats: List<CameraRecordFormat>): LinkedHashMap<VideoFormat, Long> {
        val table = LinkedHashMap<VideoFormat, Long>()
        for (format in formats) videoFormat(format)?.let { table.putIfAbsent(it, format.id) }
        return table
    }

    fun clock(seconds: Int): String = String.format(Locale.US, "%02d:%02d:%02d:00", seconds / 3600, (seconds / 60) % 60, seconds % 60)

    /** Battery, storage and shooting mode (iOS `apply(device:)` + `applyDeviceStatus`). */
    fun applyDevice(readout: CameraReadout, status: CameraStatus, pins: LunaControlPins, now: Long): CameraStatus {
        var next = status
        readout.batteryPercent?.let { next = next.copy(batteryPercent = it, charging = readout.charging) }
        val storages = readout.storages
        (storages.firstOrNull { it.location == 2 } ?: storages.firstOrNull())?.let {
            next = next.copy(internalTotalMb = (it.totalBytes / 1_000_000).toInt(), internalFreeMb = (it.freeBytes / 1_000_000).toInt())
        }
        storages.firstOrNull { it.location == 3 && it.usable }?.let {
            next = next.copy(sdTotalMb = (it.totalBytes / 1_000_000).toInt(), sdFreeMb = (it.freeBytes / 1_000_000).toInt())
        }
        if (storages.isNotEmpty()) {
            val usable = storages.filter { it.usable }
            next = next.copy(
                storageTotalMb = (usable.sumOf { it.totalBytes } / 1_000_000).toInt(),
                storageFreeMb = (usable.sumOf { it.freeBytes } / 1_000_000).toInt(),
            )
        }
        readout.shootingMode?.let { mode ->
            val wire = shootingMode(mode)
            // Keep the operator's pending mode until the camera reports it.
            if (pins::shootingMode.hold(wire, now) == null && next.shootingMode != wire) {
                next = next.clearedModeDependentCapabilities().copy(shootingMode = wire)
            }
        }
        return next
    }

    /** Exposure, EV, WB, color, format and focus (iOS `apply(settings:)`). Returns the status and the format table. */
    fun applySettings(readout: CameraReadout, status: CameraStatus, pins: LunaControlPins, now: Long): Pair<CameraStatus, LinkedHashMap<VideoFormat, Long>> {
        val table = formatTable(readout.recordFormats)
        // Nothing read yet: leave the shared "unknown" state alone.
        if (readout.recordFormats.isEmpty()) return status to table
        var next = status
        val exposure = if (status.isPhoto) readout.stillExposure ?: readout.videoExposure else readout.videoExposure ?: readout.stillExposure
        if (exposure != null) {
            // Stills report adaptive/full-auto programs (4, 5); only 1...3 fix a value.
            val mode = if (exposure.program in 1..3) CameraCommands.EXPO_MANUAL else CameraCommands.EXPO_AUTO
            val reportedIso = if (exposure.iso == 0) 0 else CameraCommands.isoIndexFromValue(exposure.iso)
            val isoIndex = pins::isoIndex.hold(reportedIso, now) ?: reportedIso ?: -1
            val denom = if (exposure.shutterSeconds > 0) (1 / exposure.shutterSeconds).roundToInt() else -1
            next = next.copy(
                expoMode = pins::expoMode.hold(mode, now) ?: mode,
                isoIndex = isoIndex,
                iso = CameraCommands.isoValue(isoIndex) ?: if (exposure.iso > 0) exposure.iso else -1,
                shutterDenom = pins::shutterDenom.hold(denom, now) ?: denom,
            )
        }
        readout.exposureBiasTenths?.let { tenths ->
            val ev = EvComp.fromThirds((tenths / 10.0 * 3).roundToInt()).rawValue
            next = next.copy(evComp = pins::ev.hold(ev, now) ?: ev)
        }
        readout.whiteBalanceKelvin?.let { kelvin ->
            val reported = if (kelvin == 0) CameraCommands.WB_AUTO to 0 else CameraCommands.WB_CUSTOM to kelvin
            val (mode, shownKelvin) = pins::whiteBalance.hold(reported, now) ?: reported
            next = next.copy(wbMode = mode, wbKelvin = if (shownKelvin > 0) shownKelvin else if (kelvin > 0) kelvin else next.wbKelvin)
        }
        readout.color?.let { profile ->
            val color = colorMode(profile)
            next = next.copy(colorMode = pins::color.hold(color, now) ?: color)
        }
        // Photo mode reports a still size (unknown here); keep the last video format.
        readout.recordFormat?.let { reported ->
            val format = videoFormat(reported) ?: return@let
            if (format.resolution == unknownResolution) return@let
            table.putIfAbsent(format, reported.id)
            val shown = pins::format.hold(format, now) ?: format
            next = next.copy(resolutionCode = shown.resolution.rawValue, fpsIndex = shown.frameRate.rawValue, fps = shown.frameRate.fps)
        }
        next = next.copy(
            availableColorModes = colorModes,
            availableVideoFormats = table.keys.sortedWith(compareBy({ it.resolution.rawValue }, { it.frameRate.fps })),
            availableIsoIndices = isoIndices,
            availableShutterDenoms = shutterDenoms,
            focusMode = when {
                readout.afMode == 1 -> CameraCommands.FOCUS_SINGLE
                readout.afMode != null || next.focusMode < 0 -> CameraCommands.FOCUS_CONTINUOUS
                else -> next.focusMode
            },
            zoomFactor = readout.zoom ?: next.zoomFactor,
        )
        return next to table
    }
}

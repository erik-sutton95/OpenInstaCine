package com.opencapture.openinstacine.monitor.session

import com.opencapture.opencine.appkit.label
import com.opencapture.opencine.core.CameraValuePin
import com.opencapture.opencine.insta360.luna.LunaSubjectTracking
import com.opencapture.opencine.insta360.shell.CameraColorProfile
import com.opencapture.opencine.insta360.shell.CameraFocusMode
import com.opencapture.opencine.insta360.shell.CameraGimbalMode
import com.opencapture.opencine.insta360.shell.CameraGimbalSpeed
import com.opencapture.opencine.insta360.shell.CameraReadout
import com.opencapture.opencine.insta360.shell.CameraRecordFormat
import com.opencapture.opencine.insta360.shell.CameraShootingMode
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraLabelProfile
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.ConnectionPhase
import com.opencapture.opencine.vocabulary.EvComp
import com.opencapture.opencine.vocabulary.FocusOption
import com.opencapture.opencine.vocabulary.FocusTrackMode
import com.opencapture.opencine.vocabulary.GimbalMode
import com.opencapture.opencine.vocabulary.GimbalSpeed
import com.opencapture.opencine.vocabulary.TrackingBox
import com.opencapture.opencine.vocabulary.VideoFormat
import com.opencapture.opencine.vocabulary.VideoFrameRate
import com.opencapture.opencine.vocabulary.VideoResolution
import kotlin.math.roundToInt
import kotlin.reflect.KMutableProperty0

/** The shell stage as the vocabulary stage the shared live chrome reads: the two enums list the same stages by the same names. */
internal fun com.opencapture.opencine.insta360.shell.ConnectionPhase.vocabularyPhase(): ConnectionPhase = ConnectionPhase.valueOf(name)

/** Optimistic values the operator asked for, held until the camera reports them (iOS `LunaControlPins`). */
/** ISO, shutter, white balance and record are not here: their pending state is the Core operation (CoreControl.kt). */
internal class LunaControlPins {
    var ev: CameraValuePin<Int>? = null
    var color: CameraValuePin<Int>? = null
    var format: CameraValuePin<VideoFormat>? = null
    var shootingMode: CameraValuePin<Int>? = null
    var gimbalMode: CameraValuePin<GimbalMode>? = null
    var gimbalSpeed: CameraValuePin<GimbalSpeed>? = null
    var focus: CameraValuePin<FocusOption>? = null
    var faceMetering: CameraValuePin<Boolean>? = null
    var photoInFlight = false

    fun clear() {
        ev = null; color = null
        format = null; shootingMode = null; gimbalMode = null; gimbalSpeed = null; focus = null; faceMetering = null
        photoInFlight = false
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

    /** Luna names for the shared mode drum (carried by [profile]). */
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
        CameraGimbalMode.FPV -> GimbalMode.FPV
        // The shell's fourth slot carries FPV-V; the official app offers no lock mode.
        CameraGimbalMode.FPV_VERTICAL -> GimbalMode.DIRECTION_LOCK
        CameraGimbalMode.LOCK, CameraGimbalMode.STABILIZED_VERTICAL -> null
    }

    /** Official Luna app names for the four modes it offers. */
    val gimbalModeLabels = mapOf(
        GimbalMode.FOLLOW to "Roll Lock", GimbalMode.TILT_LOCKED to "Roll & Tilt", GimbalMode.FPV to "FPV", GimbalMode.DIRECTION_LOCK to "FPV-V",
    )

    fun cameraGimbalMode(mode: GimbalMode): CameraGimbalMode = when (mode) {
        GimbalMode.FOLLOW -> CameraGimbalMode.ROLL_LOCK
        GimbalMode.TILT_LOCKED -> CameraGimbalMode.ROLL_TILT_LOCK
        GimbalMode.FPV -> CameraGimbalMode.FPV
        GimbalMode.DIRECTION_LOCK -> CameraGimbalMode.FPV_VERTICAL
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

    /** The official app's three AF modes (option 93); the shared FOCUS drum and chip list only these. */
    val focusOptions = listOf(FocusOption.SINGLE, FocusOption.CONTINUOUS_DEFAULT, FocusOption.PRODUCT_SHOWCASE)

    /** Luna vocabulary for the shared screens, and media served at its own path on the camera AP. */
    val profile = CameraProfile(
        labels = CameraLabelProfile(
            shootingModeLabels = shootingModeLabels,
            colorModeLabels = mapOf(CameraCommands.COLOR_NORMAL to "Standard"),
            gimbalModeLabels = gimbalModeLabels,
            focusLabels = focusOptions.map { it.chip },
            colorModes = colorModes,
            shootingModes = listOf(CameraCommands.SHOOT_VIDEO, CameraCommands.SHOOT_PHOTO,
                CameraCommands.SHOOT_TIMELAPSE, CameraCommands.SHOOT_HYPERLAPSE,
                CameraCommands.SHOOT_SUPER_NIGHT, CameraCommands.SHOOT_SLOWMO),
        ),
        media = com.opencapture.opencine.vocabulary.MediaRoute(host = "192.168.42.1", directPath = true),
    )

    fun focusOption(mode: CameraFocusMode): FocusOption = when (mode) {
        CameraFocusMode.SINGLE -> FocusOption.SINGLE
        CameraFocusMode.CONTINUOUS -> FocusOption.CONTINUOUS_DEFAULT
        CameraFocusMode.PRODUCT_SHOWCASE -> FocusOption.PRODUCT_SHOWCASE
    }

    fun cameraFocusMode(option: FocusOption): CameraFocusMode? = when (option) {
        FocusOption.SINGLE -> CameraFocusMode.SINGLE
        FocusOption.CONTINUOUS_DEFAULT -> CameraFocusMode.CONTINUOUS
        FocusOption.PRODUCT_SHOWCASE -> CameraFocusMode.PRODUCT_SHOWCASE
        FocusOption.SUBJECT_LOCK, FocusOption.REGISTERED_PRIORITY -> null
    }

    /** iOS `doubleTapTrackBox`: square on the 16:9 sensor, a fifth of the width, centred on the tap and kept in frame. */
    fun doubleTapTrackBox(x: Double, y: Double): TrackingBox {
        val w = 0.2
        val h = w * 16 / 9
        return TrackingBox((x - w / 2).coerceIn(0.0, 1 - w), (y - h / 2).coerceIn(0.0, 1 - h), w, h)
    }

    /** Shared (focusMode, focusTrack) for [option]; null blanks the readout. */
    fun withFocus(status: CameraStatus, option: FocusOption?): CameraStatus = status.copy(
        focusMode = when (option) {
            null -> -1
            FocusOption.SINGLE -> CameraCommands.FOCUS_SINGLE
            else -> CameraCommands.FOCUS_CONTINUOUS
        },
        focusTrack = when (option) {
            null -> -1
            FocusOption.PRODUCT_SHOWCASE -> FocusTrackMode.PRODUCT_SHOWCASE.raw
            else -> FocusTrackMode.DEFAULT.raw
        },
    )

    /** Shared resolution byte for a Luna frame size: DJI bytes where the shape matches, Luna bytes (0xD0...) otherwise. */
    fun resolution(width: Int, height: Int): VideoResolution {
        val long = maxOf(width, height)
        val portrait = height > width
        return when {
            width == height -> if (long == 3072) VideoResolution.P3K_1X1 else unknownResolution
            long == 1920 && !portrait -> VideoResolution.P1080
            long == 1920 -> VideoResolution.P1080_9X16
            long in 2688..2720 && !portrait -> VideoResolution.P2_7K
            long in 2688..2720 -> VideoResolution.P2_7K_9X16
            long in 2880..3072 && portrait -> VideoResolution.P3K_9X16
            long == 3840 && !portrait && height < 2000 -> VideoResolution.P4K_235
            long == 7680 && !portrait && height < 4000 -> VideoResolution.P8K_235
            long in 2880..3072 -> VideoResolution.P3K
            long == 3840 && !portrait -> VideoResolution.P4K
            long == 3840 -> VideoResolution.P4K_9X16
            long in 5120..5760 && !portrait -> VideoResolution.P6K
            long == 7680 && !portrait -> VideoResolution.P8K
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

    /** Deep Track boxes between the shared owner and the shell's overlays (same top-left frame). */
    fun trackingBox(box: LunaSubjectTracking.Box) = TrackingBox(box.x, box.y, box.width, box.height)
    fun lunaBox(box: TrackingBox) = LunaSubjectTracking.Box(box.x, box.y, box.width, box.height)

    /** Battery, storage and shooting mode (iOS `apply(device:)` + `applyDeviceStatus`). */
    fun applyDevice(readout: CameraReadout, status: CameraStatus, pins: LunaControlPins, now: Long): CameraStatus {
        var next = status
        readout.batteryPercent?.let { next = next.copy(batteryPercent = it, charging = readout.charging == true) }
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

    /** Live exposure readouts, EV, color, format and focus (iOS `apply(settings:)`). Returns the status and the format table. */
    fun applySettings(readout: CameraReadout, status: CameraStatus, pins: LunaControlPins, now: Long): Pair<CameraStatus, LinkedHashMap<VideoFormat, Long>> {
        val table = formatTable(readout.recordFormats)
        // Nothing read yet: leave the shared "unknown" state alone.
        if (readout.recordFormats.isEmpty()) return status to table
        var next = status
        val exposure = if (status.isPhoto) readout.stillExposure ?: readout.videoExposure else readout.videoExposure ?: readout.stillExposure
        // Live readouts only (Auto may report what it chose). The ISO, shutter and WB settings and
        // the exposure mode come from the Core session (CorePresentation).
        if (exposure != null) {
            next = next.copy(
                iso = if (exposure.iso > 0) exposure.iso else -1,
                shutterDenom = if (exposure.shutterSeconds > 0) (1 / exposure.shutterSeconds).roundToInt() else -1,
            )
        }
        readout.exposureBiasTenths?.let { tenths ->
            val ev = EvComp.fromThirds((tenths / 10.0 * 3).roundToInt()).rawValue
            next = next.copy(evComp = pins::ev.hold(ev, now) ?: ev)
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
            zoomFactor = readout.zoom ?: next.zoomFactor,
        )
        // AF modes the official app never offers (0, 2, 4, 5) leave the readout blank.
        val focus = readout.focusMode?.let(::focusOption)
        next = withFocus(next, pins::focus.hold(focus, now) ?: focus)
        return next to table
    }
}
